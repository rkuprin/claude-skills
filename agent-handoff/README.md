# agent-handoff

Renders a short prompt that hands bounded work to another agent — Codex.app, the codex CLI, the
claude CLI, or a fresh Claude session. One skill, three modes:

| Mode | For | Ends with |
|---|---|---|
| `task` (default) | bounded work outside the sprint ledger | a result returned to the caller |
| `visual-validation` | "implemented here, confirm it there" | test scenario + inline screenshots, for the human |
| `story-execution` | one planned sprint story, end to end | the story's late `/goal` checkpoint (after an operator brainstorm gate, for `loop: full`) |

It is a prompt renderer: it produces a task file (default `~/.handoffs/`) plus text you paste. It
never executes the work itself. Every prompt ends with `/goal` — a command in both Codex.app and
Claude Code, plain text anywhere else.

The story lifecycle contract (branching, trailers, gates, evidence, rollback) lives in
[`EXECUTION.md`](EXECUTION.md), which rendered story prompts reference by the receiving harness's
path. The prompt itself keeps only the catastrophic rules inline, with literal values.

For `loop: full` stories the contract opens with read-only investigation and an interactive
brainstorm with the operator; divergences that cross the story boundary hand back to the sprint
planner via a REPLAN event in `STORY-FEEDBACK.md`. Executors also keep a transient mail lane with the supervising planner
(`~/.sprint-mail/<repo>/<sprint>/`, via `sprint-orchestrator`'s `sprint-mail.sh`): `evidence`
posts, one blocking `question` at a time, and a terminal `concluded` outcome on every exit —
never a substitute for the git-derived state or the event protocol.

## Prerequisites

- **Anything visual targets Codex.app** — only the app renders screenshots inline; the CLI is never
  a silent substitute.
- Story-execution assumes the consuming project's AGENTS.md / CLAUDE.md supply the deploy command,
  live URL, gate commands, test accounts, and approved visual drivers — nothing is restated here.
- Installed in **both** harnesses (`./install.sh` and `CLAUDE_SKILLS_DIR=~/.codex/skills
  ./install.sh`) so the contract path resolves wherever the prompt lands.

## Use it

```
/agent-handoff                       # Claude — infers mode from what you hand it
$agent-handoff                       # Codex
/agent-handoff docs/sprints/<sprint>/07-date-presets.md   # story-execution
```

Companion to [`sprint-orchestrator`](../sprint-orchestrator/), which writes the story docs that
story-execution mode consumes — but nothing here requires a sprint: the skill is callable anytime.
