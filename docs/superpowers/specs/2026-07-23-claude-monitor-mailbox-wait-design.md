# Non-blocking Claude mailbox wait via Monitor

**Date:** 2026-07-23 (revised same day after independent Codex review — see "Review
record" at the end)
**Status:** approved, pre-plan
**Supersedes:** the Claude arm/Stop-hook wait from
`2026-07-19-unified-mailbox-wake-design.md` (Codex and Kimi paths from that spec are
untouched).

## Problem

On Claude Code the sprint-orchestrator mailbox park is `sprint-mail.sh arm --harness claude`
plus the `claude-stop-wait.sh` Stop hook: the session ends its turn and the hook holds the
Stop event open, sleep-polling the mailbox for up to 3h. While any Stop hook runs, Claude
Code shows a foreground spinner ("Waiting for sprint mailbox reply") and the session accepts
no input; Esc is the only way in, and Esc kills the hook mid-poll and orphans its wait
record. This contradicts the constitution's interaction model — "the user talks to the
orchestrator; executors talk to it through the mailbox" — because a parked supervisor is
unreachable. The operator has rejected the foreground park as not viable. The defect is
structural (a synchronous Stop hook cannot coexist with an interactive session), not a bug
in the hook.

## Decision

Replace the Claude-side wait transport with a harness-tracked **background watch task**: a
new `sprint-mail.sh watch` subcommand runs in the background while the turn genuinely ends;
its terminal output arrives as a chat event that wakes the session, and the operator keeps
the prompt throughout. The launcher is either the Monitor tool or Bash
`run_in_background` — **which one is decided by the Phase 0 probe, not by this spec** (the
harness's own guidance pairs one-shot waits with `run_in_background` and streaming watches
with Monitor; `watch` is one-shot). Codex keeps the arm/record/Stop-hook mechanism; Kimi
keeps the cron sweep. The mailbox files, cursor, and never-lost sweep invariant are
unchanged.

Alternatives rejected:

- **`asyncRewake` on the existing Stop hook** — smallest diff, but the field is thinly
  documented, has no dedup (each Stop while armed spawns another polling instance, each
  able to re-wake), and its semantics were only probed headlessly. A gamble on one bit.
- **No park on Claude** — rely solely on the per-turn cursor sweep. Zero machinery, but an
  executor question during an unattended wave waits for operator attention, which defeats
  supervised unattended waves.

## Core primitive: `sprint-mail.sh watch`

New subcommand: `sprint-mail.sh watch <sprint-dir> <globs> [timeout]` (timeout defaults
1800). A foreground poll loop, poll interval `SPRINT_MAIL_POLL` (sprint-mail.sh's existing
default: 20s — deliberate; the hooks' 2s was for a turn held open, a background watch can
afford slower polls). Differences from `wait`:

1. **Cursor-aware.** A file wakes the watch iff it matches the globs AND its basename is
   not a line in the worktree's read-cursor (`cursor_file()` — same predicate as `unread`
   and the NEW-format hook path). Pre-existing unread mail wakes it on the first poll.
   Like `unread`, it must run from the project worktree and errors out otherwise.
2. **One atomic stdout line per terminal outcome.** The launcher turns stdout into wake
   events, so the protocol is exactly one line, then exit — never multiple lines, never
   reliance on event batching:
   - Wake: one line carrying the matching paths and the guidance ("New sprint mail
     arrived: <paths> — read it and continue … sweep ALL new mail … re-arm before ending
     the turn if the wave is still running"), exit 0.
   - Timeout: one line with the per-glob-shape guidance, adapted from
     `claude-stop-wait.sh`'s case block with the "Armed mailbox wait" wording corrected to
     the watch form (`*-reply.md` → take the contract's no-reply fallback; `*-note.md` →
     dependency park, keep parking, never conclude on expiry;
     `*-question.md|*-concluded.md` → supervisor sweep and re-arm; unknown → strict
     executor fallback), exit 1.
   - Error (bad args, not in a worktree, lock conflict): one line on **stdout** (mirrored
     to stderr) — stderr alone never reaches the event stream, so a stderr-only failure
     would be a silent death, exit ≥ 2.
3. **One watch per worktree — lockfile, not records.** `watch` takes an advisory lock
   keyed by the worktree (a lockfile under the mail dir, e.g. `.watch/<cksum-of-worktree>`,
   created on start, removed on every exit path, stale-pruned by age against
   timeout + slack). A second `watch` for the same worktree fails fast with the error
   protocol above. This restores `arm`'s cross-session one-wait-per-worktree exclusion —
   a session-local task list cannot provide it (two sessions in one worktree could
   otherwise both wake on the same mail before either marks it seen) — and gives
   `supervise` its idempotence check. The lock is NOT a `.codex-waits` record: a claude
   entry there would falsely park a Codex Stop hook running in the same worktree.

No arming, no `.codex-waits` entries, no reaper. The harness owns the task lifecycle; a
dead watch is a missed wake, and the per-turn cursor sweep already catches missed wakes.

## The park

A Claude **main** session parks by launching the watch in the background and ending its
turn. The rendered instruction (from `supervise` and kickoffs) uses the probe-selected
launcher; the Monitor form, if selected:

```
Monitor(command: "'<skills-path>/sprint-orchestrator/sprint-mail.sh' watch '<sprint-dir>' '<globs>' <budget>",
        description: "sprint mailbox — <sprint>", persistent: true)
```

All rendered commands shell-quote the script path, sprint dir, and globs. `persistent:
true` (or the run_in_background equivalent) opts out of the launcher's own timeout; the
script always exits on its own (wake or timeout), and that exit delivers the guidance line
as the wake event. Budgets are unchanged: 10800 for the supervisor idle sweep, 1800 for
targeted reply waits.

**Permission posture** (parallel to the existing Kimi caveat in REFERENCE.md): the session
must be able to launch the watch **unattended** — after a wake, re-arming happens with no
operator present, and a permission prompt at that moment kills reactive supervision. The
prose documents the allowlist rule for the exact watch command; the probe verifies an
unattended re-arm actually runs. Preflight: if the Monitor tool is absent in a session,
use the Bash `run_in_background` form — same command, same protocol.

Carried-over invariants, unchanged in meaning:

- First action of every supervisor turn is the cursor sweep — a wake lost to a dead session
  or killed watch is caught on the next turn.
- Re-arm (launch a new watch) on each wake while the wave runs; a spurious wake finds
  nothing unread.
- One watch per worktree, enforced by the lockfile (above), checked by `supervise` before
  printing the park instruction.
- Executor first-action rule (new line in the claude mailwait text): on any wake — or on
  discovering it has no live watch — an executor sweeps unread reply mail before doing
  anything else, then re-arms only if still waiting.
- The mailbox is never state; `sprint-status.sh` reads neither mailbox nor cursor.
- Subagent topology unchanged: an in-session subagent cannot end its turn and be woken —
  rendered subagent kickoffs keep the non-arming fallback. Main sessions only.

## Migration — ordered, per machine

The spec's earlier claim that a leftover settings entry is inert was wrong in the presence
of file deletion: `~/.claude/settings.json` references the hook by absolute path, so
deleting `claude-stop-wait.sh` first makes the Stop hook error on every turn. The order is
mandatory:

1. Remove the `claude-stop-wait.sh` Stop group from `~/.claude/settings.json` (surgical:
   only that group; co-installed Stop hooks survive — same preservation rule as the
   installer). On this machine, done as an implementation step; for any other machine,
   README documents the manual edit. No uninstall script — the entry is one JSON group.
2. Then delete `claude-stop-wait.sh` and `install-claude-hook.sh` from the repo.
3. Drain stale claude wait records: run `sprint-mail.sh disarm` in any worktree that had
   an armed claude wait. Records do not identify their harness, so never bulk-delete
   `.codex-waits` — a Codex session's live wait may be in there.

## Touchpoints

- `sprint-mail.sh`
  - add `watch` (poll loop over the `unread` predicate + lockfile + one-line protocol).
  - `supervise --harness claude`: stop exec-ing `arm`; check the watch lock, then print
    the park instruction (same print-instructions pattern as the existing `kimi` branch),
    budget 10800, globs `*-question.md *-concluded.md`, plus the re-arm/one-watch rules.
  - `arm --harness claude`: refuse, like `arm` refuses `kimi`, pointing at
    `watch`/`supervise` — Claude has no Stop-hook wait anymore.
- `wave-handoffs.sh`: the claude `mailwait` string becomes "post your question, then
  launch (background) `sprint-mail.sh watch <sprint-dir> <story>-{SSS}-reply.md 1800` and
  END YOUR TURN — the watch event wakes you; never foreground the wait", plus the executor
  first-action sweep rule. Codex, Kimi, and subagent-topology strings unchanged.
- `agent-handoff/EXECUTION.md` (the claude arm-and-end-turn instruction, ~line 142) and
  `agent-handoff/SKILL.md` (the mailbox-wait template forms, ~lines 173 and 199): replace
  the `arm --harness claude` form with the watch form. Without this, executors following
  the contract hit `arm`'s new refusal and end their turn with **no wake at all**.
- Delete `claude-stop-wait.sh` + `install-claude-hook.sh` (after the settings edit — see
  Migration) and their tests `test-claude-stop-wait.sh`, `test-install-claude-hook.sh`.
- `test/lint-skills.sh`: drop the byte-identical body pin between the two hooks
  (`codex-stop-wait.sh` becomes the single copy; its header comment updates in the same
  commit); update every pin naming the deleted files or the Claude arm form; add pins for
  the new watch prose (supervise output, claude mailwait string, arm refusal). Same commit
  as the prose changes.
- `sprint-orchestrator/test/test-sprint-mail.sh`: watch cases — cursor-aware wake (unread
  file wakes, seen file does not; pre-existing unread wakes immediately), one-line
  protocol per outcome, timeout guidance per glob shape, exit codes, lock conflict, lock
  cleanup on every exit path, refusal of `arm --harness claude`.
- `sprint-orchestrator/test/test-wave-handoffs.sh`: claude mailwait assertions move to the
  watch form.
- `REFERENCE.md` "Mailbox mechanics": rewrite the Claude bullet to the watch park
  (launcher per probe outcome); drop the `install-claude-hook.sh` reference; add the
  permission-posture sentence.
- `README.md` (sprint-orchestrator) "Reactive waits on Claude": rewrite — nothing to
  install; document the watch park and the migration steps for machines that ran the old
  installer.
- Root `README.md` and `INSTALL.md`: update the lines naming the Claude hook/installer.
- `SKILL.md`: no structural change expected; verify the mailbox-watching prose (reactive,
  never hand-polling) still reads true and touch only if a sentence names the hook.

## Phase 0 — transport-selection probe

Monitor and Bash `run_in_background` are **peer candidates**; the probe picks the launcher
and its findings are recorded in the implementation plan before any transport prose is
written. Headless `claude -p` is not evidence for longevity (print-mode background tasks
are reaped after the final result — both the 2026-07-19 probe and the official docs say
so); the long-lived facts need a live interactive session.

Probe checklist, per candidate:

- Pre-existing unread mail: wake on first poll, exactly one event.
- Mail landing while the session is idle: does the event **re-invoke the model** (not just
  render for the operator)?
- Mail landing mid-turn (model working) and mid-conversation (operator typing): event
  delivery and ordering.
- Multiple unread files: still exactly one event (the one-line protocol).
- Unattended re-arm: after a wake, the model launches the next watch with no operator
  present and no permission prompt.
- Timeout and nonzero exit: the exit reaches the model with the guidance line.
- Session close/resume and Esc/cancel: what dies, what survives, lockfile state after.
- Multi-hour silence (the 3h supervisor budget) on the winning candidate.

**Decision rule:** prefer the candidate that passes idle re-invocation and unattended
re-arm; if both pass, prefer `run_in_background` (the harness's own one-shot idiom, no
persistent flag needed). If neither survives a 3h budget, shorten the supervisor budget
(e.g. 3600s re-arms) rather than reverting to the blocking hook — the blocking park is
rejected regardless.

## Testing

- `test-sprint-mail.sh` and `test-wave-handoffs.sh` cover `watch` and the rendered forms
  (see Touchpoints).
- `test/lint-skills.sh` pins the new prose forms and drops dead pins, same commit.
- Phase 0 probe results recorded in the implementation plan before the transport prose is
  finalized.

## Review record

Independent Codex review (gpt-5.6-sol, xhigh, 2026-07-23) found seven issues; this
revision adopts: the ordered migration (settings edit before file deletion; no bulk record
deletion), the missed touchpoints (`agent-handoff` contract files, root README/INSTALL,
three test files), the one-atomic-stdout-line event protocol with errors mirrored to
stdout, the per-worktree watch lockfile replacing the false "duplicates are harmless"
claim, the transport-selection reframing of Phase 0 with the expanded checklist, the
permission-posture requirement, and the small corrections (20s poll default, adapted — not
verbatim — timeout text, shell-quoting). Rejected as overreach for personal local tooling:
a version/supported-environment matrix, hosted-remote positions, an uninstall script and
compatibility shim (ordering makes them unnecessary), a JSON event format (the consumer is
a model; one prose line), and a full executor-recovery overhaul (the no-wake-after-death
hole predates this change; the executor first-action sweep line covers it).
