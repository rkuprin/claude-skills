# Non-blocking Claude mailbox wait via Monitor

**Date:** 2026-07-23
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

Replace the Claude-side wait transport with the harness's **Monitor** tool: a background
task whose stdout lines arrive as chat events, while the turn genuinely ends and the
operator keeps the prompt. Codex keeps the arm/record/Stop-hook mechanism; Kimi keeps the
cron sweep. The mailbox files, cursor, and never-lost sweep invariant are unchanged.

Alternatives rejected:

- **`asyncRewake` on the existing Stop hook** — smallest diff, but the field is thinly
  documented, has no dedup (each Stop while armed spawns another polling instance, each
  able to re-wake), and its semantics were only probed headlessly. A gamble on one bit.
- **No park on Claude** — rely solely on the per-turn cursor sweep. Zero machinery, but an
  executor question during an unattended wave waits for operator attention, which defeats
  supervised unattended waves.

## Core primitive: `sprint-mail.sh watch`

New subcommand: `sprint-mail.sh watch <sprint-dir> <globs> [timeout]` (timeout defaults
1800). A foreground poll loop like `wait`, with three differences:

1. **Cursor-aware.** A file wakes the watch iff it matches the globs AND its basename is
   not a line in the worktree's read-cursor (`cursor_file()` — same predicate as `unread`
   and the NEW-format hook path). Like `unread`, it must run from the project worktree and
   errors out otherwise.
2. **Self-explaining output on stdout** (stdout is the Monitor event stream; the hook used
   stderr because Stop hooks feed stderr to the model):
   - On the first unread batch: the matching paths, one per line, then the wake guidance
     line ("New sprint mail arrived … sweep ALL new mail … re-arm before ending the turn if
     the wave is still running"), then exit 0.
   - At budget: the per-glob-shape timeout guidance, moved verbatim from
     `claude-stop-wait.sh`'s case block (`*-reply.md` → take the contract's no-reply
     fallback; `*-note.md` → dependency park, keep parking, never conclude on expiry;
     `*-question.md|*-concluded.md` → supervisor sweep and re-arm; unknown → strict
     executor fallback), then exit 1.
3. **No records.** No arming, no `.codex-waits` entry, no identity matching, no reaper.
   The harness owns the task lifecycle; a dead watch is just a missed wake, and the
   per-turn cursor sweep already catches missed wakes.

Poll interval: reuse `SPRINT_MAIL_POLL` (default 2s), same as `wait`.

## The park

A Claude **main** session parks by starting a Monitor and ending its turn:

```
Monitor(command: "<skills-path>/sprint-orchestrator/sprint-mail.sh watch <sprint-dir> '<globs>' <budget>",
        description: "sprint mailbox — <sprint>", persistent: true)
```

`persistent: true` opts out of the harness's 1h monitor cap; the script always exits on its
own (wake or timeout), and that exit delivers the guidance text as the wake event. Budgets
are unchanged: 10800 for the supervisor idle sweep, 1800 for targeted reply waits.

Carried-over invariants, unchanged in meaning:

- First action of every supervisor turn is the cursor sweep — a wake lost to a dead session
  or killed monitor is caught on the next turn.
- Re-arm (start a new watch) on each wake while the wave runs; a spurious wake finds
  nothing unread.
- One watch per park: the session's own task list shows a live watch — do not start a
  second. A duplicate is harmless (the cursor dedups the sweep) but noisy.
- The mailbox is never state; `sprint-status.sh` reads neither mailbox nor cursor.
- Subagent topology unchanged: an in-session subagent cannot end its turn and be woken —
  rendered subagent kickoffs keep the non-arming fallback. Main sessions only.

## Touchpoints

- `sprint-mail.sh`
  - add `watch` (poll loop over the `unread` predicate + guidance output).
  - `supervise --harness claude`: stop exec-ing `arm`; print the Monitor park instruction
    (same print-instructions pattern as the existing `kimi` branch), budget 10800,
    globs `*-question.md *-concluded.md`, plus the re-arm/one-watch rules.
  - `arm --harness claude`: refuse, like `arm` refuses `kimi`, pointing at
    `watch`/`supervise` — Claude has no Stop-hook wait anymore.
- `wave-handoffs.sh`: the claude `mailwait` string becomes "post your question, then start
  a Monitor (persistent) running `sprint-mail.sh watch <sprint-dir>
  <story>-{SSS}-reply.md 1800` and END YOUR TURN — the watch event wakes you; never
  foreground the wait." Codex, Kimi, and subagent-topology strings unchanged.
- Retire `claude-stop-wait.sh` and `install-claude-hook.sh` (delete both).
- `test/lint-skills.sh`: drop the byte-identical body pin between the two hooks
  (`codex-stop-wait.sh` becomes the single copy; its header comment updates in the same
  commit); update every pin that names the deleted files or the Claude arm form; add pins
  for the new watch prose. Same commit as the prose changes.
- `sprint-orchestrator/test/test-sprint-mail.sh`: watch cases — cursor-aware wake (unread
  file wakes, seen file does not), timeout guidance per glob shape, exit codes, refusal of
  `arm --harness claude`.
- `REFERENCE.md` "Mailbox mechanics": rewrite the Claude bullet to the Monitor park; drop
  the `install-claude-hook.sh` reference.
- `README.md` "Reactive waits on Claude": rewrite — nothing to install; document the
  Monitor park; add a one-line cleanup note for machines that ran the old installer:
  delete the `claude-stop-wait.sh` Stop group from `~/.claude/settings.json`. A leftover
  entry is inert — with nothing arming records, the hook exits 0 instantly — so cleanup is
  manual, not scripted (decided: no uninstall script).
- `SKILL.md`: no structural change expected; verify the mailbox-watching prose (reactive,
  never hand-polling) still reads true and touch only if a sentence names the hook.

## Phase 0 — probe before building

Two assumptions are load-bearing and unproven; the design dies without them:

1. A persistent Monitor's event **re-invokes the model** while the session sits idle — not
   just a UI line for the operator.
2. A persistent Monitor **survives hours of silence** (a 3h supervisor park) and still
   delivers.

One live-session probe settles both, mirroring the 2026-07-19 Stop-hook probe (headless
`claude -p --settings` where possible, live interactive session for the idle-wake fact).
Also verify the session stays interactive while a watch runs — the point of the change.

**Fallback if (1) fails:** the same `watch` command runs under Bash `run_in_background`,
whose exit is documented to re-invoke the session. One substitution in the printed
instructions; everything else in this spec stands. The 2026-07-19 probe's note about a
~1-2min background-task reaper was observed headlessly and must be re-tested
interactively before trusting this fallback for long budgets.

If both transports fail the longevity test, shorten the supervisor budget (e.g. 3600s
re-arms) rather than reverting to the blocking hook — the blocking park is rejected
regardless.

## Testing

- `test/test-sprint-mail.sh` covers `watch` behavior (see Touchpoints).
- `test/lint-skills.sh` pins the new prose forms (Monitor park instruction in supervise
  output, claude mailwait string, arm refusal) and drops dead pins, same commit.
- Phase 0 probe results recorded in the implementation plan before the transport prose is
  finalized.
