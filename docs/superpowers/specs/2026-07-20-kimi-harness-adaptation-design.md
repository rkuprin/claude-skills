# Kimi as a third sprint-orchestrator harness: cron-scheduled mailbox waits — design

Date: 2026-07-20
Skills touched: `sprint-orchestrator`, `agent-handoff` (plus repo `README.md`, `INSTALL.md`,
`AGENTS.md`, `test/lint-skills.sh`)
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
   (`~/.agents/skills/...`), the kickoff's `Mailbox wait:` and contract-path lines, and the README
   install story all name only Claude and Codex.

Kimi facts verified against the official docs (2026-07-20): `disable-model-invocation: true` is
honored (kebab-case accepted) — the skill stays manual-only and is invocable via
`/skill:sprint-orchestrator`; `~/.agents/skills/` is a standard user-level scan dir (the symlink
already exists on this machine); hooks are `[[hooks]]` entries in `~/.kimi-code/config.toml`,
timeout 1–600s, fail-open on error/timeout; `CronCreate` delivers a recurring prompt to an idle
session (1-minute granularity, coalescing, 7-day stale auto-delete, session-scoped).

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

## Non-goals

- **No Kimi Stop hook, no `install-kimi-hook.sh`.** Its absence is a lint invariant.
- **No ladder changes.** No `driver_hint: kimi`, no Kimi model column, no tier-row edits — the
  4-row cross-file ladder sync pins stay as they are. Kimi-bound stories render an advisory
  Launch line (§4).
- **No cron waits on Claude/Codex.** Neither CLI exposes a scheduled-prompt mechanism (checked
  2026-07-20 against `claude --help` / `codex --help` on this machine), and the hook wait is
  strictly better where it works.
- **No `type: flow` frontmatter.** Kimi honors `disable-model-invocation`; a second guard is
  redundant.
- **No changes to** `sprint-status.sh`, both stop-wait hooks and their installers,
  `agents/openai.yaml`, trailer/state derivation, or the mailbox file format. Mixed-harness waves
  (Kimi supervisor, Codex/Claude executors) already interoperate through plain files.

## Design

### 1. The Kimi wait: two cron forms

The shared pin fragment for both forms and the `arm` refusal: **"Kimi has no Stop-hook wait"**.

**Supervisor idle watch** (replaces `arm --harness … '*-question.md *-concluded.md' 10800`).
Rendered into `sprint-orchestrator/SKILL.md` "Supervising the Wave" beside the two arm forms:

> On Kimi there is no Stop hook to arm: create ONE recurring cron task (CronCreate, every 5
> minutes) whose prompt reads: "Supervisor sweep for \<sprint-dir\>: run
> `sprint-mail.sh unread <sprint-dir> '*-question.md *-concluded.md'` then
> `sprint-mail.sh unread <sprint-dir> '*'` from the project root, read and `seen` everything,
> act per Supervising the Wave; when every story is DONE or DISPOSED, delete this cron task;
> otherwise end the turn." The recurring task replaces the arm/re-arm loop — one task per wave,
> not one per wake.

**Executor targeted reply wait** (replaces `arm … {NN}-{SSS}-reply.md 1800`). Rendered as the
kimi variant of the kickoff's `Mailbox wait:` line (agent-handoff template, wave-handoffs
renderer) and mirrored in `agent-handoff/EXECUTION.md`:

> you are a Kimi session — Kimi has no Stop-hook wait. Post your question, then use your
> CronCreate tool to schedule a recurring check (every 3 minutes) whose prompt reads: "Check the
> sprint mailbox for {NN}-{SSS}-reply.md via `sprint-mail.sh unread {SPRINT_DIR}` — if it landed,
> mark it `seen`, delete this cron task, and continue the story; if the 1800s reply budget from
> the question's post has elapsed, delete this cron task and take the contract's no-reply
> fallback; otherwise end the turn." Then END YOUR TURN — the cron nudge wakes you; never poll or
> background the wait.

`{NN}`, `{SPRINT_DIR}` resolve at render time; `{SSS}` stays literal (the runtime question
sequence), exactly as in the codex/claude forms. The executor fills the concrete deadline when
creating the task.

Correctness rests on the durable read-cursor, unchanged: a missed nudge is caught by the next
one, and a forgotten cron degrades to today's no-wake fallback (next-turn cursor sweep). Both
prompts are self-deleting — the task removes itself on reply, on deadline, or on wave conclusion —
and Kimi's 7-day stale auto-delete bounds any leak.

### 2. `sprint-mail.sh` — one guard, no new mechanism

`arm` stays `codex|claude`-only. A `kimi` branch is added ahead of the generic refusal:

```
sprint-mail: arm refuses kimi — Kimi has no Stop-hook wait; a Kimi session waits via a recurring
cron sweep (see the kickoff's Mailbox wait line or sprint-orchestrator/SKILL.md 'Supervising the
Wave')
```

Exit 2, no record written. The usage lines stay `arm --harness <codex|claude>` (lint-pinned,
unchanged); the header comment gains one line stating Kimi sessions wait via cron sweeps.

### 3. `agent-handoff` — kimi target, fourth wait variant

- **Targets** gain `kimi` (an interactive Kimi CLI session). Resolution order unchanged:
  capability → the user's explicit say → availability → affinity. `loop: full` stories may target
  `kimi` (it is an interactive main session); in-session Kimi subagents (Agent tool) get the same
  non-arming fallback as on the other harnesses — that variant's prose changes "on either
  harness" → "on any harness".
- **Contract path** for kimi targets: `~/.agents/skills/agent-handoff/EXECUTION.md`.
- **Launch line** for kimi targets: never blank, never a ladder cell —
  `Launch: Kimi session · model per session config (tier {X} advisory — the ladder has no Kimi cell)`.
- **`Mailbox wait:` template line** gains the kimi cron form (§1) as a fourth alternative in the
  braces; the bullet above the template explains the kimi resolution alongside the existing three.

### 4. `wave-handoffs.sh` — `--wait-form` override

New optional trailing flag:
`wave-handoffs.sh <sprint-dir> <wave> --topology <main-session|subagent> [--wait-form <codex|claude|kimi>]`.
Default (absent): today's per-story resolution from `driver_hint`. A present flag forces the
named form for every story on the sheet — `--wait-form kimi` renders the kimi cron wait form and
the `~/.agents` contract path throughout (the operator pastes a batch into Kimi sessions when
Claude/Codex capacity is tight); `codex`/`claude` force those forms the same way. Fail-closed in
the script's existing style: an unknown value errors; `--wait-form` combined with
`--topology subagent` errors (the subagent topology already overrides the wait line; a wait-form
there is meaningless). Launch lines stay per-story — they are operator advice, overridden at
paste time regardless. The sheet header notes when a `--wait-form` override was applied, and the
subagent-topology comment's "both harness forms" phrasing is swept to "any harness" here too.

### 5. `sprint-orchestrator/SKILL.md` prose

- Frontmatter `description:` becomes a double-quoted scalar (it gains a colon via the Kimi
  spelling — repo rule) and reads: invoke explicitly with `/sprint-orchestrator` (Claude),
  `$sprint-orchestrator` (Codex), or `/skill:sprint-orchestrator` (Kimi).
- "Story State Is Derived": helper-path examples gain
  `~/.agents/skills/sprint-orchestrator/sprint-status.sh … # Kimi`.
- "Supervising the Wave": the Kimi sweep form (§1) follows the codex/claude arm sentences; the
  "both harnesses arm their sprint Stop hook" phrasing is reworked so the three wait mechanisms
  read as equals. The existing lint-pinned arm strings are not touched.
- "Executing Direct Stories In-Session": names Kimi's Agent tool as an in-session subagent
  transport with the same subagent topology and non-arming fallback.
- "The Planner Handoff": one clause noting `/goal` is native on all three harnesses.

### 6. READMEs, INSTALL.md, AGENTS.md

- `sprint-orchestrator/README.md`: Use-it block gains `/skill:sprint-orchestrator # Kimi`;
  sprint-status examples gain the `~/.agents` path; a new "### Reactive waits on Kimi — nothing
  to install" subsection states the cron design (no hook, no installer, the session schedules its
  own sweeps; wake latency is the cron period).
- `INSTALL.md`: documents `CLAUDE_SKILLS_DIR=~/.agents/skills ./install.sh` for the Kimi skills
  dir and states no hook wiring is needed for Kimi.
- Repo `README.md`: Kimi row in the install/use summary, matching the above.
- `AGENTS.md`: one line under Frontmatter rules — Kimi honors `disable-model-invocation` (hidden
  from the model's listing, manual via `/skill:<name>`); `~/.agents/skills/` is the shared skills
  dir Kimi scans.

### 7. Error handling and degradation

- `arm --harness kimi` → exit 2 with the redirect (§2); no record created (tested).
- `--wait-form` bad value, or combined with `--topology subagent` → exit 2 with usage (tested).
- Forgotten cron after a question → no wakes; the next-turn cursor sweep still catches the reply
  (late, never lost) — same terminal state as today's missed wake.
- Leaked cron after wave end → the sweep prompt finds a concluded/absent mailbox and deletes
  itself; 7-day stale auto-delete is the backstop.
- Session closed mid-wait → cron dies with the session; the ownership-transfer precondition
  (transport confirmed dead) is unchanged.

### 8. Tests and lint

New `test/lint-skills.sh` pins (all in the same commit as the prose they check):

- `ORCH`: `/skill:sprint-orchestrator`; `^description: "` (quoted scalar); the supervisor sweep
  fragment `recurring cron`; `~/.agents/skills/sprint-orchestrator/sprint-status.sh`.
- `AH`: targets line includes `kimi`; `~/.agents/skills/agent-handoff/EXECUTION.md`;
  `Kimi has no Stop-hook wait`.
- `AHEXEC`: `Kimi has no Stop-hook wait`; `CronCreate` (the kimi bullet's scheduled-check form).
- `SMAIL`: `Kimi has no Stop-hook wait` (the §2 refusal — same shared fragment, case included).
- `WHS`: `--wait-form`; `Kimi has no Stop-hook wait` (the rendered kimi form).
- `ORCH_README`: `/skill:sprint-orchestrator`; `Reactive waits on Kimi`.
- `INSTALL`: `CLAUDE_SKILLS_DIR=~/.agents/skills`.
- Negative pins: `install-kimi-hook` absent from ORCH, ORCH_README, INSTALL, AH, AHEXEC, WHS,
  SMAIL. All existing pins (the two arm strings, ladder sync, guard keys) must keep passing.

Suite additions in dialect (bash + grep, hermetic fixtures):

- `test-sprint-mail.sh`: `arm --harness kimi` exits 2, stderr carries the refusal, and no wait
  record appears in `$MAIL_ROOT/.codex-waits/`.
- `test-wave-handoffs.sh`: a fixture wave rendered with `--topology main-session --wait-form kimi`
  carries the kimi cron wait form and `~/.agents` contract path in every kickoff;
  `--wait-form bogus` and `--wait-form kimi` + `--topology subagent` both exit 2; default render
  output unchanged (covered by existing pins).

Full suite at the end: `test/lint-skills.sh`, `codex/test/test.sh`, all
`sprint-orchestrator/test/*.sh`. Plus `bash -n` on every touched script.

### 9. Live verification (manual, operator)

1. Fresh Kimi session → `/skill:sprint-orchestrator` loads the skill; it never auto-fires
   (absent from the model's listing).
2. Optional end-to-end: a scratch sprint with one `loop: direct` story executed by a Kimi main
   session — question posted, cron wake, reply seen, cron deleted.
