---
name: agent-handoff
description: "Render a short handoff prompt that sends bounded work to another agent — Codex.app, codex CLI, claude CLI, a fresh Claude session, or a Kimi session. Modes: task (bounded work, report back), visual-validation (Codex.app confirms UI changes with inline screenshots), story-execution (kick off one planned sprint story end to end). Triggers: hand this off, delegate this, ask Codex to validate this visually, kick off story NN."
---

# agent-handoff — hand bounded work to another agent

One skill, three modes. It renders a prompt to paste (and usually a task file for the receiver to
read); it never executes the work itself. Before rendering, confirm there is a bounded task and an
observable goal — if either is missing, ask. Then state which mode and target you picked and why,
in one line.

## Mode and target

An explicit mode argument wins. Otherwise infer: the input is a story doc → story-execution; the
ask names surfaces or screenshots → visual-validation; anything else → task.

Targets: `codex-app` | `codex-cli` | `claude-cli` | `claude-session` | `kimi`. Resolve in order: required
capability → the user's explicit say → current availability (ask the user if unknown — Claude and
Codex subscriptions deplete independently) → affinity. Affinity, in two lines: Codex leans
well-documented, difficult-but-straightforward work where creativity is not welcome and attention
and diligence are — mechanistic sweeps, devops, browser-driving; Fable (Claude) and Kimi lean
creative, exploratory, decision-heavy, ambiguous work. Capability outranks affinity: anything that
must show rendered screenshots targets
`codex-app` — the CLI cannot render images and is never a silent substitute. If Codex.app capacity
is unavailable, visual work is blocked; say so instead of downgrading.

Before any codex kickoff, ask: does this need a browser, or a human in the loop for any other
reason? If neither, it runs as a CLI command — target `codex-cli` (`codex exec`), not `codex-app`.

## Model and effort — the Launch line

Every rendered handoff begins with a Launch line addressed to YOU,
the operator, placed outside the fenced prompt block — it is launch advice, never part of
what gets pasted into the executor:

    Launch: Codex.app · gpt-5.6-terra · xhigh   (tier B — same-tier alternative: opus on Claude)

CLI targets get a recommended base invocation instead — you complete repo and prompt transport:
`codex exec --dangerously-bypass-approvals-and-sandbox -m gpt-5.6-terra -c model_reasoning_effort=xhigh` /
`claude --model opus --effort xhigh`. Non-interactive codex sessions run in bypass mode —
`--dangerously-bypass-approvals-and-sandbox` (skip all confirmations, no sandbox) is the codex
CLI's wording for Claude's bypass-permissions mode: a `codex exec` run has no operator at the
terminal, so an approval prompt would only stall it.

| Tier | Claude (`--model`) | Codex (`-m`) | Kimi | Depth default |
|------|--------------------|--------------|------|---------------|
| S | `fable` | — | `kimi-k3` | high (xhigh only when capability-limited) |
| A | — | `gpt-5.6-sol` | — | xhigh |
| B | `opus` | `gpt-5.6-terra` | — | xhigh |
| C | `sonnet` | `gpt-5.6-luna` | — | high |

Resolve model and effort from the story's `tier:` × `driver_hint:` against this ladder at render
time — the tier letter governs, not the story's inline comment. An absent `effort:` means the
row's depth default, resolved now; an explicit `effort:` (with its `effort_why:`) wins.
`driver_hint: either` lists both cells. `orchestrate: true` renders ultracode on Claude targets
and `ultra` on the tier's codex model — Luna has no `ultra`, so an orchestrated C-tier codex
story bumps to Terra. A doc without `tier:` (pre-convention): infer a tier from the work's
nature using the grading in `sprint-orchestrator/SKILL.md`, use the current cell default, assume
no orchestration — and say so in the one-line mode/target statement. Never render a blank Launch
line. Depth defaults are operator policy for today's model generation; revisit when a generation
changes. Kimi targets render the ladder's Kimi cell where one exists — tier S only: `kimi-k3`
sits between fable and sol in capability and is fable's designed substitute when Claude capacity
is out. A tier-S Kimi target renders `Launch: Kimi session · kimi-k3 · high (tier S)`; other
tiers have no Kimi cell and run the session's configured model:
`Launch: Kimi session · model per session config (tier {X} advisory — the ladder has a Kimi cell only at tier S)`.

The Launch line is a recommendation — you decide at paste time. Two swaps worth knowing: when
Claude capacity is free, a B story can run `fable` at low/medium instead of `opus` at xhigh —
early evidence says that matches for similar burn; and when fable is at capacity, an S story
moves to `kimi-k3` — the designed substitute, not a drop to tier A.

## The prompt shape (every mode)

```
<Title — becomes the receiving session's name>

Read the task file: <path>
Use skills: <skills to invoke on the other side — Claude Code, Codex, and Kimi share this skills repo>
<2-3 lines of live context>

/goal <observable done — almost always present>
```

`/goal` ends every prompt regardless of target. It is a command in both Codex.app and Claude Code,
and anywhere else it is plain text that still carries the goal.

## The task file

Write it to `~/.handoffs/YYYY-MM-DD-<slug>.md` (`mkdir -p ~/.handoffs`) — outside any git worktree,
which is deleted long before anyone re-reads it — unless an existing doc (story doc, spec) already
covers the task; then point at that instead. Contents: the task, current state, relevant
paths/symbols/anchors, constraints. The receiver only reads the task file. Never put credentials or
secrets in one.

## Mode: task (default)

Bounded work outside the sprint ledger; the deliverable is a result returned to the caller — a
report, a fixed config, a research answer. No lifecycle machinery: no trailers, no merge order, no
deploy gates. Never use task mode for a numbered sprint story — that is story-execution, whatever
its `loop:` value.

Grade the work with the ladder's tiers yourself (same grading as the sprint planner) and fold
the pick into the one-line mode/target statement: mode, target, tier, model, effort, why.

## Mode: visual-validation

For "implemented here, confirm it there". **Report-only by default:** the receiver drives the flows
and reports. It fixes nothing unless the task file carries an explicit mutation grant naming the
files it may touch — and then there is a single writer: the sending session stops editing those
files until the report is back.

Beyond the standard contents, the task file must carry:

- the changed surfaces as `(route, state)` pairs and what correct looks like;
- the exact workspace identity: repo root or worktree path, branch, HEAD SHA, whether uncommitted
  changes are present — without this a fresh session may never see the sender's uncommitted work;
- how to launch: dev server command, port, test account.

Target is `codex-app`, always; the Launch line defaults to `gpt-5.6-luna` · `high` — routine
mechanical driving needs no more (and must not silently inherit a global `ultra` config).
Escalate tier or effort when the ask involves ambiguous design judgment, accessibility review,
or broad multi-surface validation. The receiver ends its reply with the test scenario (steps, expected
vs observed) and inline screenshots grouped per surface — written for the user, not for another
agent. Each shot names its driver and viewport; one line each, no provenance table.

Prompt template (fill everything; keep it this short):

```
Visual validation: <what changed, three words>

Read the task file: ~/.handoffs/<date>-<slug>.md
Use skills: <only if one applies; often none>
<one line: what was implemented and where it runs>
Report only — do not edit files<, except the mutation grant in the task file>.
End your reply with the test scenario (steps, expected vs observed) and inline screenshots grouped
per surface, one line of driver+viewport each. That ending is for the user, not for another agent.

/goal I can read your reply top to bottom and know, from the scenario and the inline screenshots,
whether <the change> renders and behaves correctly on every listed surface.
```

## Mode: story-execution

Input: one planned story doc (typically written by `sprint-orchestrator`; read it and its
`00-overview.md` first). Render the lean kickoff prompt below — every value literal, resolved at
render time; no placeholders left for the executor.

- `execution:` in the story doc becomes the EXECUTION MODE line: `autonomous` →
  `AUTONOMOUS — merge, deploy, verify on prod.`; `stop-at-pr` →
  `STOP AT PR — DO NOT MERGE OR DEPLOY.`
- `loop:` sets the planning-depth sentence: `full` → run the contract's
  investigation + interactive brainstorm phase with the operator first; `direct` → the story is
  fully defined — go straight to a short TDD plan. `loop: direct` also allows a `codex-cli` /
  `claude-cli` / subagent target; `loop: full` stories belong in an interactive session
  (`codex-app`, `claude-session`, or `kimi`).
- The `Use skills:` line comes from the story's `flow:` — `mechanical` and `design-heavy` →
  superpowers:test-driven-development; `flow: direction` → none: the deliverable is a dossier,
  so no implementation skill applies. Never render superpowers:brainstorming into a kickoff:
  the design conversation is the contract's own brainstorm gate, routed to the session's real
  counterparty, while that skill's approval gate points at a user who may not be in the loop.
- The story's `driver_hint:` / `driver_why:` frontmatter is the affinity input at the final
  resolution step; capability and the user's explicit say still outrank it.
- `tier:` / `effort:` / `orchestrate:` resolve to the Launch line per the ladder above; render
  the Launch line before the fenced kickoff prompt, never inside it.
- The contract path is spelled for the target harness:
  `~/.codex/skills/agent-handoff/EXECUTION.md` for Codex targets,
  `~/.claude/skills/agent-handoff/EXECUTION.md` for Claude targets,
  `~/.agents/skills/agent-handoff/EXECUTION.md` for kimi targets.
- The `Mailbox wait:` line resolves on harness × topology, so the executor's comms are
  settled before the story starts. Every paste target is a main session: Codex targets render
  the codex arm-and-end-turn form, Claude targets (claude-cli, claude-session) render the
  claude arm-and-end-turn form (`arm --harness claude …`), kimi targets render the
  cron-scheduled wait (Kimi has no Stop-hook wait — CronCreate a recurring check, mark the
  goal blocked so its continuation turns don't starve cron delivery, end the turn; the cron
  prompt resumes the goal with UpdateGoal active on the reply). An in-session subagent dispatch
  (allowed for `loop: direct` only) renders the non-arming fallback instead, on any
  harness — the Stop hook never fires for a subagent, so it must not pretend to wait; a
  `direct` story that genuinely needs a blocking reply is mis-scoped and must be
  re-planned as a main-session story. `{SPRINT_DIR}` is the literal sprint directory path; `{SSS}` stays
  literal — it is the question's runtime sequence number.
- Pre-render claim check: `git fetch origin`, then verify the story's exact `branch:` value exists
  on NO ref and no worktree is pinned to it (`git branch -a`, `git worktree list`). A pure claim —
  the branch with zero story commits — already means DOING; trailer-derived status lags it, so a
  TODO reading is never clearance to dispatch (rp-20260712-1). If claimed, report the branch,
  worktree, and HEAD instead of rendering a kickoff.
- Takeover kickoffs — re-dispatch or rescue authorized by the supervisor's ownership transfer
  (see `sprint-orchestrator/SKILL.md`) — add one line after `Sprint identity:`:
  `Resume grant: resume designated branch {BRANCH} at {SHA} — {WHAT REMAINS}`.
  Ordinary kickoffs never carry it, and for them the pre-render claim check refusal stands unchanged.

```
{SPRINT} · Story {NN}: {Three Descriptive Words}

You are executing ONE story end-to-end.
EXECUTION MODE: {AUTONOMOUS — merge, deploy, verify on prod. | STOP AT PR — DO NOT MERGE OR DEPLOY.}
Sprint identity: {SPRINT}. Designated claim branch: `{BRANCH}`.
Mailbox: {MAILBOX} — post evidence, questions, and your terminal outcome per the contract's Mailbox section.
Mailbox wait: {post your question, then `~/.codex/skills/sprint-orchestrator/sprint-mail.sh arm --harness codex {SPRINT_DIR} {NN}-{SSS}-reply.md 1800` (SSS = your question's sequence) and END YOUR TURN — the armed Stop hook wakes you on the reply; never poll or background the wait. | post your question, then `~/.claude/skills/sprint-orchestrator/sprint-mail.sh arm --harness claude {SPRINT_DIR} {NN}-{SSS}-reply.md 1800` (SSS = your question's sequence) and END YOUR TURN — the armed Stop hook wakes you on the reply; never poll or background the wait. | you are a Kimi session — Kimi has no Stop-hook wait. Post your question and note the post time, then use your CronCreate tool to schedule a recurring check (every 3 minutes) whose prompt reads: "Sprint mailbox wait for {NN}-{SSS}-reply.md: run `~/.agents/skills/sprint-orchestrator/sprint-mail.sh unread {SPRINT_DIR} '{NN}-{SSS}-reply.md'` from the worktree. If the reply landed at or before <deadline — a literal epoch, post time + 1800s; compare against `stat -f %m` of the reply file>: read it, mark it seen, delete this cron task with CronDelete, then resume the waiter's goal with UpdateGoal active and continue. If it landed later, or the deadline has passed with no reply: delete this cron task and take the contract's no-reply fallback. Otherwise end the turn — the goal stays blocked." Then mark your goal blocked — this is the designed wait protocol, not a failure: the blocker is an external condition (the mailbox reply) and the cron task is the wake; an active goal's continuation turns starve cron delivery, so the blocked state IS the park. Then END YOUR TURN — the cron nudge wakes you; never poll or background the wait. | you are an in-session subagent — the Stop hook never fires for you, so you cannot end your turn and be woken. Do not pretend to wait: if you post a blocking question, treat it as no reply and take the contract's fallback path now.}
Reviews & approvals: the sprint orchestrator is your only counterparty — route spec reviews,
design sign-off, and every open decision to it via the Mailbox above; never seek approval from
whoever is at this terminal. Decisions in the story doc, 00-overview.md, and this kickoff are
already approved — do not re-open them as a new gate.
Read first: {STORY_DOC}, 00-overview.md, STORY-FEEDBACK.md, and repo conventions
(AGENTS.md / CLAUDE.md). If any are absent from this worktree, read them from trunk with
`git show origin/main:<path>` — never copy them in. Product scope and decisions there are
settled by default; the operator may amend them at the brainstorm gate, and divergences follow
the contract's handback protocol.
Execution contract: {~/.codex|~/.claude}/skills/agent-handoff/EXECUTION.md — follow it exactly.
Planning depth: {run the contract's investigation + interactive brainstorm phase with the operator
first | the story is fully defined — go straight to a short TDD plan}.
Use skills: {from the story's flow — e.g. superpowers:test-driven-development; `flow: direction` → none}
Hard rules: every commit carries `Story: {NN}` and `Sprint: {SPRINT}` (verbatim);
never `git checkout main`; if designated branch `{BRANCH}` already exists on any ref the story is
taken — stop (unless this kickoff carries a resume grant); check, create, and release only that exact branch;
on handback publish the REPLAN event (docs-only, no trailers) and release the claim branch;
never leave prod broken.

/goal {STORY_GOAL}
```

The first line is the story's `conversation:` value, so the receiving session names itself after
the sprint-scoped story and its tracker card. `{SPRINT}` and `{BRANCH}` are the story doc's exact
frontmatter values. The sprint is the directory basename verbatim; anything else makes the story
invisible to sprint status forever.
`{MAILBOX}` is the literal mail directory — `~/.sprint-mail/<repo-basename>/{SPRINT}/`, with
the repo basename resolved at render time (the git common dir's parent directory, exactly as
`sprint-mail.sh` derives it).
