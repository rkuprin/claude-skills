# Supervisor sweep enforcement + wait-machinery guards — design

Date: 2026-07-20
Skills touched: `sprint-orchestrator` (plus repo `test/lint-skills.sh` and new tests under
`sprint-orchestrator/test/`). `agent-handoff` is untouched — the executor side is not implicated.
Source: 2026-07-20 evening session — post-mortem of the `2026-07-20-remediation-sprint-1` wave
(lead-us), hours after `2026-07-20-kimi-harness-adaptation-design.md` landed. Operator decisions
locked in the brainstorm:

- **Scope: all three findings** from the post-mortem (over sweep-only, or sweep + park-timeout).
- **Approach: hybrid subcommand + slim prose** (over prose-only hardening, which repeats the exact
  failure mode being fixed, and over full tooling, which grows `sprint-mail.sh` past the need).

## Problem

Three defects observed in one live wave, in descending order of blast radius.

### 1. The Kimi supervisor never parked — correct prose, no execution

`SKILL.md`'s Supervising section already prescribes the Kimi wait: one recurring CronCreate sweep
every 5 minutes, goal-blocked as the park (pinned by lint: "kimi supervisor sweep is a recurring
cron"). The wave's Kimi supervisor never created the task — zero CronCreate calls in its session
wire. Contributing factors, both confirmed from the wire:

- The instruction sits mid-paragraph in a ~25-line block covering all three harnesses.
- The pattern says "mark your goal blocked", but the session's `/goal` was the **planning** goal,
  completed at dispatch time. Supervision ran goal-less; the park mechanism had nothing to attach
  to, and the model improvised by doing nothing.

Consequence: three blocking executor questions (01-002, 03-005, 07-003, posted 18:36–18:39) sat
~25 minutes and were answered at 19:03 only because an unrelated background-task notification
happened to resume the session. Had no nudge arrived, the executors' 1800s reply waits would have
timed out into the no-reply fallback (handback/blocked) on work that was actually fine.

### 2. `arm --harness` cannot catch a harness/kickoff mismatch

Story 04a's kickoff was rendered for Claude (`driver_hint: claude`, `arm --harness claude`,
`~/.claude/skills/...` paths) but pasted into a **Codex** session. It worked only by accident:
`arm` writes to the shared `~/.sprint-mail/.codex-waits/` regardless of `--harness`, and the Codex
Stop hook matched the record by worktree. The `--harness` verification checked the wrong harness's
hook config and never noticed.

### 3. The timeout wake text is wrong for dependency parks

Stories 03 and 07 parked on `NN-*-note.md` gate-waits. When those waits expire with no note, the
hook's timeout text instructs: "take the contract's no-reply fallback (handback/blocked) and post
your terminal concluded" — correct for a reply-wait, wrong for a deliberate dependency park, where
the right action is to re-arm and keep parking.

## Design

### §1 `sprint-mail.sh supervise --harness <codex|claude|kimi> <sprint-dir>`

New subcommand. The supervisor runs it after every mailbox sweep, replacing the per-harness arm
sentences in prose.

- **codex**: arms `'*-question.md *-concluded.md'` with budget 1800 (today's codex supervisor
  form). **claude**: same glob, budget 10800. Both are idempotent: if a wait is already armed for
  this worktree, print "already armed" and exit 0 (no disarm-first dance on re-arm).
- **kimi**: arms nothing (no hook exists to fire). Prints the complete, ready-to-paste CronCreate
  call to stdout: the cron expression (every 5 minutes), the full sweep prompt with `<sprint-dir>`
  already resolved, and these behaviors baked into the printed text:
  - "CronList first — if this sweep task already exists, do nothing" (idempotency; bash cannot
    see the session's cron store, so the check is delegated to the model via the printed prompt).
  - The blocked-goal park **and the goal-less fallback**: "if you have an active goal, mark it
    blocked — the blocked state is the park; if you have no active goal, simply ending the turn
    is the park — cron fires land whenever the session is idle." (Finding 1's exact hole.)
  - "CronDelete this task when every story is DONE or DISPOSED; re-create it if a fire arrives
    marked stale (7-day expiry) and the wave is still running."
  - The permission-posture requirement (unattended mailbox commands; a sweep stalled on an
    approval panel wakes no one) stays in SKILL.md prose.
- **SKILL.md**: the Supervising section's per-harness arm sentences (`SKILL.md:215-236`) shrink
  to: cursor sweep first (unchanged), then `supervise --harness <your harness> <sprint-dir>` and
  follow its output. One reference line keeps the arm forms findable ("supervise is
  `arm --harness codex <sprint-dir> '*-question.md *-concluded.md' 1800` under the hood", and the
  claude 10800 form) so existing lint pins survive. The why — never-lost cursor sweep, blocked
  goal as the park, permission posture — stays in place.
- The cron prompt text printed by `supervise --harness kimi` carries the same sweep semantics the
  SKILL.md prose describes today (`unread` blocking kinds, then `unread '*'`, read, `seen`), so
  prose and tool cannot drift apart silently — lint pins both.

### §2 arm harness-mismatch warning

In `arm`, after the existing hook-reference verification, walk the parent process chain from `$$`
(`ps -o ppid= -o comm=`) looking for a `codex`, `claude`, or `kimi` binary.

- Confident detection **and** detected ≠ `--harness` → print a loud stderr warning naming both,
  **then arm anyway**. The wait record is harness-agnostic by design; 04a's accidental success was
  useful, and refusal would break legitimate cross-harness launches. The warning exists so the
  mismatch surfaces in the session's own output at the moment it happens.
- No harness detected in the chain → silence. Never cry wolf in plain shells or tests.
- `SPRINT_MAIL_ASSUME_HARNESS=<codex|claude|kimi>` env var overrides process detection —
  test-only hook, documented as such in the script's header comment, making the warning path
  deterministic under any test runner.

### §3 Timeout wake text branches on the armed glob

In `codex-stop-wait.sh` **and** `claude-stop-wait.sh`, the no-mail timeout branch picks its
message from the glob stored in the wait record (line 2):

- glob contains `-reply.md` → question-wait timeout: current text unchanged (no-reply fallback,
  post terminal `concluded`).
- glob contains `-note.md` → dependency park: "the gate you parked on is still closed — re-arm
  the same wait and keep parking, unless the dependency's premise changed; do NOT post a terminal
  `concluded` merely because the wait expired."
- glob contains `-question.md` or `-concluded.md` (supervisor sweep form) → current "sweep, then
  re-arm if the wave is still running" text.

The mail-found path is unchanged in both hooks.

## Files touched

- `sprint-orchestrator/sprint-mail.sh` — `supervise` subcommand; arm mismatch warning;
  `SPRINT_MAIL_ASSUME_HARNESS` test hook; usage text.
- `sprint-orchestrator/codex-stop-wait.sh`, `sprint-orchestrator/claude-stop-wait.sh` — §3
  timeout-text branch.
- `sprint-orchestrator/SKILL.md` — Supervising section slimmed to `supervise`; reference line
  keeping the arm forms.
- `test/lint-skills.sh` — pins for: `supervise` usage line; kimi cron payload markers (CronList
  first, goal-less fallback, CronDelete on conclusion); the park-timeout wording; keep existing
  arm-form pins valid via the SKILL.md reference line. Any pin whose string moves is updated in
  the same commit.
- `sprint-orchestrator/test/` — new bash+grep tests (below).

`agent-handoff/EXECUTION.md`, `agent-handoff/SKILL.md`, `wave-handoffs.sh`: untouched. Executor
waits, kickoff rendering, and the mailbox format do not change.

## Tests

All bash + grep, matching repo convention; run beside `test/lint-skills.sh` and the existing
`sprint-orchestrator/test/` suites.

1. `supervise --harness kimi <sprint-dir>` output contains: the resolved sprint dir, `CronList`,
   the goal-less fallback wording, `CronDelete`, and does **not** create a `.codex-waits` record.
2. `supervise --harness codex` arms once; a second invocation exits 0 with "already armed" and
   exactly one record exists.
3. `arm` with `SPRINT_MAIL_ASSUME_HARNESS` set opposite to `--harness` warns on stderr and still
   arms; with matching values, no warning; unset and no harness in the process chain, no warning.
4. Hook timeout branches (both stop hooks): temp `SPRINT_MAIL_ROOT`, hand-written wait records
   with `-reply.md` / `-note.md` / supervisor globs, `SPRINT_MAIL_POLL=1`, ~2s timeout → assert
   the matching stderr branch each time.

## Non-goals

- No change to the mailbox format, read-cursor, or wait-record layout (the glob the §3 branch
  reads is already line 2 of the record).
- No Kimi Stop-hook work; the cron sweep remains Kimi's only wait mechanism.
- No cross-session supervisor liveness watchdog (cron stores are session-private; checked by
  CronList inside the session, not from outside).
- No retroactive fix for the currently-parked 03/07 waits — their 1800s timeout fires under the
  old text; the operator is aware. All future parks get the new text.

## Risks

- **Prose/tool drift**: the kimi cron semantics now live in two places (SKILL.md prose, supervise
  output). Mitigated by lint pins on both; the lint rule is that changing one requires changing
  the other in the same commit.
- **False-positive mismatch warnings** (§2): a session launched through wrappers could misdetect.
  Warning-only by design; silence when unsure.
- **`supervise` idempotency vs. legitimate re-arm**: "already armed" must not suppress re-arming
  after a hook fired — hook deletes the record on fire, so a post-wake supervise always re-arms.
