---
name: agent-handoff
description: "Render a short handoff prompt that sends bounded work to another agent — Codex.app, codex CLI, claude CLI, or a fresh Claude session. Modes: task (bounded work, report back), visual-validation (Codex.app confirms UI changes with inline screenshots), story-execution (kick off one planned sprint story end to end). Triggers: hand this off, delegate this, ask Codex to validate this visually, kick off story NN."
---

# agent-handoff — hand bounded work to another agent

One skill, three modes. It renders a prompt to paste (and usually a task file for the receiver to
read); it never executes the work itself. Before rendering, confirm there is a bounded task and an
observable goal — if either is missing, ask. Then state which mode and target you picked and why,
in one line.

## Mode and target

An explicit mode argument wins. Otherwise infer: the input is a story doc → story-execution; the
ask names surfaces or screenshots → visual-validation; anything else → task.

Targets: `codex-app` | `codex-cli` | `claude-cli` | `claude-session`. Resolve in order: required
capability → the user's explicit say → current availability (ask the user if unknown — Claude and
Codex subscriptions deplete independently) → affinity. Affinity, in two lines: Codex leans
mechanistic, devops, and browser-driving work; Claude leans creative, frontend-heavy, ambiguous
work. Capability outranks affinity: anything that must show rendered screenshots targets
`codex-app` — the CLI cannot render images and is never a silent substitute. If Codex.app capacity
is unavailable, visual work is blocked; say so instead of downgrading.

## The prompt shape (every mode)

```
<Title — becomes the receiving session's name>

Read the task file: <path>
Use skills: <skills to invoke on the other side — Claude Code and Codex share this skills repo>
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

Target is `codex-app`, always. The receiver ends its reply with the test scenario (steps, expected
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
- `loop:` sets the planning-depth sentence: `full` → run the contract's self-directed
  brainstorm → spec → plan phase first; `direct` → the story is fully defined, go straight to a
  short TDD plan. `loop: direct` also allows a `codex-cli` / `claude-cli` / subagent target;
  `loop: full` stories belong in an interactive session (`codex-app` or `claude-session`).
- The story's `driver_hint:` / `driver_why:` frontmatter is the affinity input at the final
  resolution step; capability and the user's explicit say still outrank it.
- The contract path is spelled for the target harness:
  `~/.codex/skills/agent-handoff/EXECUTION.md` for Codex targets,
  `~/.claude/skills/agent-handoff/EXECUTION.md` for Claude targets.

```
Story {NN}: {Three Descriptive Words}

You are executing ONE story end-to-end.
EXECUTION MODE: {AUTONOMOUS — merge, deploy, verify on prod. | STOP AT PR — DO NOT MERGE OR DEPLOY.}
Read first: {STORY_DOC}, 00-overview.md, STORY-FEEDBACK.md, and repo conventions
(AGENTS.md / CLAUDE.md). If any are absent from this worktree, read them from trunk with
`git show origin/main:<path>` — never copy them in. Product scope and decisions there are SETTLED;
stop and ask for a wrong premise or genuine product ambiguity (the contract's other interrupts
still apply).
Execution contract: {~/.codex|~/.claude}/skills/agent-handoff/EXECUTION.md — follow it exactly.
Planning depth: {run the contract's self-directed brainstorm → spec → plan phase first | the story
is fully defined — go straight to a short TDD plan}.
Use skills: {from the story's flow — e.g. superpowers:test-driven-development}
Hard rules: every commit carries `Story: {NN}` and `Sprint: {SPRINT}` (verbatim);
never `git checkout main`; if sprint/{NN}-* already exists on any ref the story is taken — stop;
never leave prod broken.

/goal {STORY_GOAL}
```

The first line is the story's `conversation:` value, so the receiving session names itself after
the story and its tracker card. `{SPRINT}` is the story doc's `sprint:` frontmatter value — the
sprint directory's basename, verbatim; anything else makes the story invisible to sprint status
forever.
