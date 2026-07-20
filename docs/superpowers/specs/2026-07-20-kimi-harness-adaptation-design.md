# Kimi as a third sprint-orchestrator harness: cron-scheduled mailbox waits — design

Date: 2026-07-20 (rev 3 — rev 2 after the Codex gate; rev 3 amends the §1 forms per the §9
live-probe findings)
Skills touched: `sprint-orchestrator`, `agent-handoff` (plus repo `README.md`, `CLAUDE.md` —
`AGENTS.md` is a symlink to it — `INSTALL.md`, `test/lint-skills.sh`)
Source: 2026-07-20 session — assessment of sprint-orchestrator against the Kimi Code CLI harness,
followed by a brainstorming pass. Two operator decisions locked there:

- **Scope: orchestrator + executor.** Kimi sessions may plan/supervise sprints AND execute pasted
  story kickoffs as main sessions. No tier-ladder column for Kimi — a Kimi session runs whatever
  model it is configured with; the ladder's claude/codex cells stay unchanged.
- **Wait mechanism: cron-scheduled sweeps.** Chosen over (b) a chunked Stop-hook re-block chain
  (depends on Kimi allowing unlimited consecutive `Stop` blocks — undocumented; Claude caps at 8 —
  plus a model wake every ~10 min and a third hook copy to maintain) and (c) a hook+cron hybrid
  (two mechanisms for one guarantee; the cron alone provides correctness). Claude and Codex keep
  their Stop-hook arm-and-end-turn waits untouched: near-instant wake, no per-interval model wake,
  no scheduled-task lifecycle. Cron is the right tool for Kimi specifically — its hook timeout is
  capped at 600s with fail-open on timeout, which silently kills the hold-the-turn design — not an
  upgrade to be ported.

Codex gate: one pass, 2026-07-20 (sol/xhigh, session 019f7ee7). Verdict: do not implement as
originally written — six blockers, all confirmed valid on re-weighing (the load-bearing Kimi
claims cross-checked against Kimi's own cron/goal/permission semantics) and resolved below:
the spec'd cron command was unrunnable (§1), unattended sweeps can stall on approval prompts
(§2), "cron dies with the session" was false (§7), the `/goal` × parked-wait interaction is
unverified (§8 probe), `--wait-form` rendered contradictory sheets (§4, now `--target`), and the
reply deadline had a check-order race (§1). Baseline suites green at review time (lint 253/0,
mailbox 51/0, renderer 62/0).

## Problem

1. **A Kimi session cannot arm.** `sprint-mail.sh arm` accepts only `--harness codex|claude` and
   hard-errors otherwise, and the skill forbids the remaining alternative ("watch the mailbox
   reactively — never by hand-polling"). A Kimi supervisor would catch mail only when the user
   happens to prompt.
2. **The Stop-hook wait design does not port.** Kimi's `Stop` event has the right semantics
   (blockable; exit 2 + stderr re-enters the turn as a continuation message), but hook `timeout`
   is capped at 600s and a timeout is fail-open — the turn just ends, mid-wait, with no message.
   The 1800s/10800s budgets cannot be held by one hook invocation, and a re-block chain depends on
   an undocumented consecutive-block limit.
3. **Prose gaps.** Invocation spelling (`/skill:sprint-orchestrator` on Kimi), skills-dir paths
   (`~/.agents/skills/...`), the kickoff's `Mailbox wait:` and contract-path lines, the README
   install story, and the "run the planner on Anthropic models" launch advice all name only
   Claude and Codex.

Kimi facts verified against the official docs (2026-07-20): `disable-model-invocation: true` is
honored (kebab-case accepted) — the skill stays manual-only and is invocable via
`/skill:sprint-orchestrator`; `~/.agents/skills/` is a standard user-level scan dir (the symlink
already exists on this machine); hooks are `[[hooks]]` entries in `~/.kimi-code/config.toml`,
timeout 1–600s, fail-open on error/timeout; cron tasks are session-scoped, fire only while the
session is idle, persist across exit and **revive on session resume**, coalesce missed fires, and
auto-delete after 7 days with one final `stale: true` fire; goal mode auto-continues a session
across turns; tool calls run behind the session's permission settings. Two load-bearing
interactions were verified **live** (§9 probe): goal-mode continuation turns starve cron
delivery, and a blocked goal idles the session so fires land.

## Goals

1. **A Kimi main session can supervise a wave to conclusion** — reactive mailbox wake via a
   recurring cron sweep, with the same never-lost guarantee the durable read-cursor provides today.
2. **A Kimi main session can execute a pasted story kickoff**, including the blocking
   question→reply wait, via a rendered cron form it cannot improvise.
3. **`arm --harness kimi` fails loud and redirects** to the cron form instead of arming a dead wait.
4. **Zero mechanism changes for Claude/Codex** — hooks, installers, record format, and their prose
   forms are byte-identical before and after.
5. **Every new pinned string lands in `test/lint-skills.sh` in the same change** (repo rule:
   a passing lint that no longer checks the real string is worse than no lint).
6. **Unattended operation is a stated preflight**, not a surprise: the session's permission
   posture must let mailbox commands and cron management run without an operator present (§2).

## Non-goals

- **No Kimi Stop hook, no `install-kimi-hook.sh`.** Its absence is a lint invariant.
- **No ladder changes.** No `driver_hint: kimi`, no Kimi model column, no tier-row edits — the
  4-row cross-file ladder sync pins stay as they are. Kimi-bound stories render an advisory
  Launch line (§3, §4).
- **No cron waits on Claude/Codex.** Neither CLI exposes a scheduled-prompt mechanism (checked
  2026-07-20 against `claude --help` / `codex --help` on this machine), and the hook wait is
  strictly better where it works.
- **No `type: flow` frontmatter.** Kimi honors `disable-model-invocation`; a second guard is
  redundant.
- **No changes to** `sprint-status.sh`, both stop-wait hooks and their installers,
  `agents/openai.yaml`, trailer/state derivation, or the mailbox file format. Mixed-harness waves
  (Kimi supervisor, Codex/Claude executors) already interoperate through plain files.
- **No redesign of Claude/Codex session-resume hazards.** The revived-session ownership problem
  (§7) is specified for Kimi only; the analogous armed-record case on the other harnesses is
  noted, not fixed.

## Design

### 1. The Kimi wait: two cron forms

The shared pin fragment for both forms and the `arm` refusal: **"Kimi has no Stop-hook wait"**.
Both forms spell the helper's full path (`~/.agents/skills/sprint-orchestrator/sprint-mail.sh` —
the bare command is not on `PATH`) and pass `unread` its required glob argument.

**Supervisor idle watch** (replaces `arm --harness … '*-question.md *-concluded.md' 10800`).
Rendered into `sprint-orchestrator/SKILL.md` "Supervising the Wave" beside the two arm forms:

> On Kimi there is no Stop hook to arm: create ONE recurring cron task (CronCreate, every 5
> minutes) whose prompt reads: "Supervisor sweep for \<sprint-dir\>: run
> `~/.agents/skills/sprint-orchestrator/sprint-mail.sh unread <sprint-dir> '*-question.md *-concluded.md'`
> then `~/.agents/skills/sprint-orchestrator/sprint-mail.sh unread <sprint-dir> '*'` from the
> project root, read and `seen` everything. If you found mail: resume the goal with UpdateGoal
> active, act per Supervising the Wave, then mark the goal blocked again before ending the turn
> if the wave is still running. When every story is DONE or DISPOSED, delete this cron task. If
> this fire arrives marked stale (7-day expiry) and the wave is still running, re-create the same
> task. Otherwise end the turn — the goal stays blocked." Then mark your goal blocked: an active
> goal's continuation turns starve cron delivery (fires land only at idle), so the blocked state
> IS the park. The recurring task replaces the arm/re-arm loop — one task per wave, not one per
> wake.

**Executor targeted reply wait** (replaces `arm … {NN}-{SSS}-reply.md 1800`). Rendered as the
kimi variant of the kickoff's `Mailbox wait:` line (agent-handoff template, wave-handoffs
renderer) and mirrored in `agent-handoff/EXECUTION.md`:

> you are a Kimi session — Kimi has no Stop-hook wait. Post your question and note the post
> time, then use your CronCreate tool to schedule a recurring check (every 3 minutes) whose
> prompt reads: "Sprint mailbox wait for {NN}-{SSS}-reply.md: run
> `~/.agents/skills/sprint-orchestrator/sprint-mail.sh unread {SPRINT_DIR} '{NN}-{SSS}-reply.md'`
> from the worktree. If the reply landed at or before \<deadline — a literal epoch, post time +
> 1800s; compare against `stat -f %m` of the reply file\>: read it, mark it `seen`, delete this
> cron task with CronDelete, then resume the waiter's goal with UpdateGoal active and continue.
> If it landed later, or the deadline has passed with no reply: delete this cron task and take
> the contract's no-reply fallback. Otherwise end the turn — the goal stays blocked." Then mark
> your goal blocked — this is the designed wait protocol, not a failure: the blocker is an
> external condition (the mailbox reply) and the cron task is the wake. An active goal's
> continuation turns starve cron delivery (fires land only at idle), so the blocked state IS the
> park. Then END YOUR TURN — the cron nudge wakes you; never poll or background the wait.

`{NN}`, `{SPRINT_DIR}` resolve at render time; `{SSS}` stays literal (the runtime question
sequence), exactly as in the codex/claude forms. The executor computes the deadline epoch once
(`date +%s` + 1800) and writes it literally into the cron prompt, and the check compares the
reply file's `stat -f %m` epoch against it — no timezone reasoning in the loop (a probe session
nearly fumbled local-vs-UTC mtime formatting; epochs remove the class). A reply that arrived
late is void even when discovered before the next sweep, and one that arrived in time is valid
even when discovered after it.

Correctness rests on the durable read-cursor, unchanged: a missed nudge is caught by the next
one, and a forgotten cron degrades to today's no-wake fallback (next-turn cursor sweep). Both
prompts are self-deleting — on reply, on deadline, on wave conclusion — and the supervisor
prompt self-renews on the 7-day stale fire.

### 2. Unattended operation is a launch preflight

A parked Kimi supervisor or executor is woken by cron with no operator present. Every tool call
still runs behind the session's permission settings, so a sweep that needs bash
(`sprint-mail.sh`), `CronCreate`, or `CronDelete` can stall on an approval panel indefinitely.
The spec therefore adds launch advice (sprint-orchestrator README "Where to run it", mirrored in
the SKILL.md supervising paragraph): the Kimi session must run with a permission posture that
lets the mailbox commands and cron management execute unattended (an auto permission mode, or
session-approved allow rules for exactly those commands). If cron itself is unavailable in the
environment, the Kimi wait degrades to the contract's existing no-wait fallback — the REPLAN
handback protocol — same as any harness with an unwired hook.

### 3. `agent-handoff` — kimi target, fourth wait variant

- **Targets** gain `kimi` (an interactive Kimi CLI session); the target-universe line and the
  "Claude Code and Codex share this skills repo" line gain the third harness. Resolution order
  unchanged: capability → the user's explicit say → availability → affinity. `loop: full` stories
  may target `kimi` (it is an interactive main session); in-session Kimi subagents (Agent tool)
  get the same non-arming fallback as on the other harnesses — that variant's prose changes
  "on either harness" → "on any harness".
- **Contract path** for kimi targets: `~/.agents/skills/agent-handoff/EXECUTION.md`.
- **Launch line** for kimi targets: never blank, never a ladder cell —
  `Launch: Kimi session · model per session config (tier {X} advisory — the ladder has no Kimi cell)`.
- **`Mailbox wait:` template line** gains the kimi cron form (§1) as a fourth alternative in the
  braces; the bullet above the template explains the kimi resolution alongside the existing three.

### 4. `wave-handoffs.sh` — `--target` harness override

New optional trailing flag:
`wave-handoffs.sh <sprint-dir> <wave> --topology <main-session|subagent> [--target <codex|claude|kimi>]`.
A present flag overrides harness resolution for **every** story on the sheet — wait form,
contract path, and Launch cell together, so the sheet never pairs a Kimi-only fenced prompt with
a "Launch: opus" line. `--target kimi` renders the §1 cron wait form, the `~/.agents` contract
path, and the §3 advisory Launch line throughout (the operator pastes a batch into Kimi sessions
when Claude/Codex capacity is tight); `codex`/`claude` force those harnesses' forms and Launch
cells the same way. Absent: today's per-story resolution from `driver_hint`. Fail-closed in the
script's existing style: an unknown value errors; `--target` combined with
`--topology subagent` errors (the subagent topology already overrides the wait line; a target
there is meaningless). The sheet header notes when a `--target` override was applied, and the
subagent-topology comment's "both harness forms" phrasing is swept to "any harness" here too.

### 5. `sprint-orchestrator/SKILL.md` prose

- Frontmatter `description:` becomes a double-quoted scalar (it gains a colon via the Kimi
  spelling — repo rule) and reads: invoke explicitly with `/sprint-orchestrator` (Claude),
  `$sprint-orchestrator` (Codex), or `/skill:sprint-orchestrator` (Kimi).
- "Story State Is Derived": helper-path examples gain
  `~/.agents/skills/sprint-orchestrator/sprint-status.sh … # Kimi`.
- Plan session step 5: the capacity question asks about all three harnesses ("how Claude/Codex/Kimi
  capacity looks"), not only the first two.
- "Supervising the Wave": the Kimi sweep form (§1) follows the codex/claude arm sentences; the
  "both harnesses arm their sprint Stop hook" phrasing is reworked so the three wait mechanisms
  read as equals; the §2 permission preflight is named in one clause. The existing lint-pinned
  arm strings are not touched.
- "Ownership Transfer": the Kimi death clause (§7).
- "Executing Direct Stories In-Session": names Kimi's Agent tool as an in-session subagent
  transport with the same subagent topology and non-arming fallback.
- "The Planner Handoff": one clause noting `/goal` is native on all three harnesses.

### 6. READMEs, INSTALL.md, CLAUDE.md

- `sprint-orchestrator/README.md`: Use-it block gains `/skill:sprint-orchestrator # Kimi`;
  sprint-status examples gain the `~/.agents` path; a new "### Reactive waits on Kimi — nothing
  to install" subsection states the cron design (no hook, no installer, the session schedules its
  own sweeps; wake latency is the cron period; §2 permission preflight). "Where to run it" gains
  a Kimi clause: the Anthropic-model advice governs the claude/codex choice only; a Kimi planner
  runs its session-configured model.
- `INSTALL.md`: documents `CLAUDE_SKILLS_DIR=~/.agents/skills ./install.sh` for the Kimi skills
  dir and states no hook wiring is needed for Kimi.
- Repo `README.md`: Kimi row in the install/use summary, matching the above.
- `CLAUDE.md` (the file `AGENTS.md` symlinks to): one line under Frontmatter rules — Kimi honors
  `disable-model-invocation` (hidden from the model's listing, manual via `/skill:<name>`);
  `~/.agents/skills/` is the shared skills dir Kimi scans.

### 7. Error handling and degradation

- `arm --harness kimi` → exit 2 with the redirect (§8), no record created (tested).
- `--target` bad value, or combined with `--topology subagent` → exit 2 with usage (tested).
- Forgotten cron after a question → no wakes; the next-turn cursor sweep still catches the reply
  (late, never lost) — same terminal state as today's missed wake.
- Leaked cron after wave end → the sweep prompt finds a concluded/absent mailbox and deletes
  itself; the 7-day stale auto-delete is the backstop, and the supervisor prompt self-renews
  across it while the wave runs.
- **Kimi cron tasks persist across session exit and revive on `kimi resume`.** "Terminal closed"
  is therefore NOT evidence of death for a Kimi transport. The ownership-transfer precondition
  for a Kimi executor or supervisor is: the old session's cron task deleted and its goal
  ended/blocked, or the operator's explicit commitment that the session will never be resumed.
  Without one of those, a resumed session can wake on its stale cron and keep writing to a
  transferred branch — and because read-cursors are keyed by worktree root, not session, a
  resumed old supervisor can additionally consume and `seen` mail before its successor processes
  it. (The analogous hazard exists on Claude/Codex via persistent arm records in a resumed
  session; out of scope here — see Non-goals.)

### 8. `sprint-mail.sh` — one guard, no new mechanism

`arm` stays `codex|claude`-only. A `kimi` branch is added ahead of the generic refusal:

```
sprint-mail: arm refuses kimi — Kimi has no Stop-hook wait; a Kimi session waits via a recurring
cron sweep (see the kickoff's Mailbox wait line or sprint-orchestrator/SKILL.md 'Supervising the
Wave')
```

Exit 2, no record written. The usage lines stay `arm --harness <codex|claude>` (lint-pinned,
unchanged); the header comment gains one line stating Kimi sessions wait via cron sweeps.

### 9. Probe results: `/goal` × parked cron wait (2026-07-20, live scratch session)

Every kickoff ends in `/goal`, and Kimi goal mode auto-continues a session across turns — so
the spec's original "END YOUR TURN and idle" assumption needed live verification. A two-cycle
scratch probe (`/tmp/kimi-probe`, fixture story + mailbox) settled it:

1. **An active goal starves cron delivery.** Continuation turns arrived every ~15–50s; the
   session never idled, and the cron fire was held indefinitely — `nextFireAt` stayed pinned at
   the first due time through four fire windows. A cron wait inside an active goal never fires.
2. **A blocked goal is the park.** Marking the goal blocked stopped the continuations instantly;
   the held fires delivered within seconds (`coalescedCount=3` — coalescing is benign: the
   cursor sweep only cares about latest state). Marking blocked on a *first* wait needed no
   audit history when the prompt framed it as the designed wait protocol.
3. **Self-resume works.** On an on-time reply the session ran read → `seen` → CronDelete →
   `UpdateGoal active` with no user deferral, driven only by the cron prompt's instruction.
4. **Deadline judgment must use epochs.** The probe session nearly misjudged an mtime comparison
   across local/UTC formats; the §1 form compares `stat -f %m` against a literal deadline epoch.

The §1 forms above carry the amendments: mark-blocked as part of the wait, `UpdateGoal active`
in the reply branch, "the goal stays blocked" in the keep-waiting branch, epoch deadlines. The
deadline path (180s, no reply → self-delete + fallback) exercised the same already-proven
mechanics.

### 10. Tests and lint

New `test/lint-skills.sh` pins (all in the same commit as the prose they check):

- `ORCH`: `/skill:sprint-orchestrator`; `^description: "` (quoted scalar); the supervisor sweep
  fragment `recurring cron`; `~/.agents/skills/sprint-orchestrator/sprint-status.sh`.
- `AH`: targets line includes `kimi`; `~/.agents/skills/agent-handoff/EXECUTION.md`;
  `Kimi has no Stop-hook wait`.
- `AHEXEC`: `Kimi has no Stop-hook wait`; `CronCreate` (the kimi bullet's scheduled-check form).
- `SMAIL`: `Kimi has no Stop-hook wait` (the §8 refusal — same shared fragment, case included).
- `WHS`: `--target`; `Kimi has no Stop-hook wait` (the rendered kimi form).
- `ORCH_README`: `/skill:sprint-orchestrator`; `Reactive waits on Kimi`.
- `INSTALL`: `CLAUDE_SKILLS_DIR=~/.agents/skills`.
- Negative pins: `install-kimi-hook` absent from ORCH, ORCH_README, INSTALL, AH, AHEXEC, WHS,
  SMAIL. All existing pins (the two arm strings, ladder sync, guard keys) must keep passing.

Suite additions in dialect (bash + grep, hermetic fixtures):

- `test-sprint-mail.sh`: `arm --harness kimi` exits 2, stderr carries the refusal, and no wait
  record appears in `$MAIL_ROOT/.codex-waits/`.
- `test-wave-handoffs.sh`: a fixture wave rendered with `--topology main-session --target kimi`
  matches a pinned golden block — the kimi cron wait form (full helper path, glob argument),
  the `~/.agents` contract path, and the advisory Launch line in every kickoff, header note
  included; `--target bogus` and `--target kimi` + `--topology subagent` both exit 2; default
  render output unchanged (covered by the existing pinned-output cases; any drift there fails
  loudly at implementation time).

These tests pin rendered output and exit behavior only. The permission posture, the `/goal`
interaction, and the revived-session ownership rule are not unit-testable in this dialect —
they are covered by the §9 probe and the operator smoke test below.

Full suite at the end: `test/lint-skills.sh`, `codex/test/test.sh`, all
`sprint-orchestrator/test/*.sh`. Plus `bash -n` on every touched script.

### 11. Live verification (operator)

1. ~~The §9 probe~~ — done 2026-07-20, findings folded into §1 (rev 3).
2. Fresh Kimi session → `/skill:sprint-orchestrator` loads the skill; it never auto-fires
   (absent from the model's listing).
3. End-to-end: a scratch sprint with one `loop: direct` story executed by a Kimi main session —
   question posted, goal blocked, cron wake, reply seen, goal resumed, cron deleted.
