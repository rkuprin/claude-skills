# Project Stage — design

Date: 2026-07-21
Status: approved in brainstorm, pending spec review

## Context

Different projects carry different exposure: a throwaway playground, an internal tool, a
pre-launch product, and a live product with users should not be planned with the same
rigor. The stage must be declared once (not asked every sprint), inherited by the sprint
orchestrator, and evolve at explicit moments ("we're public now"). It calibrates the
Critic and the planning gates — but through the manager's judgment, not through a
mechanized per-stage posture matrix: depending on the nature of the project and the
stage, things may stand different, and weighing that is what the management layer is for.

## Decisions from the brainstorm

- **Scope:** calibrates the Critic and the planning gates, via the planner's judgment.
- **Taxonomy:** four named stages — `playground`, `internal`, `pre-launch`, `live`.
- **Transitions:** detect + operator decides (forward-only or re-baseline) — a named
  operator seam.
- **Placement:** folded into Vital Signs as a standing attribute beside the three
  measures; the transition seam is added to the Mandate's named veto seams.
- **Explicitly rejected:** any per-stage posture table (it mechanizes the judgment
  layer); sprint-level declaration (asks every sprint); a hardcoded decision matrix in
  SKILL.md (wrong register).

## Design

### Declaration (mechanics → REFERENCE.md)

- Format: one line — `Project stage: playground | internal | pre-launch | live` — in the
  project's `AGENTS.md` or `CLAUDE.md`, or a path named by the operator.
- Discovery order mirrors the tracker binding: operator-named path → `AGENTS.md` →
  `CLAUDE.md`.
- Undeclared: the planner asks once at the brief gate and offers to write the line. If
  the operator declines, the planner records its working assumption in `00-overview.md`
  and proceeds — mentioned once, never nagged.
- Recording: `00-overview.md` carries `Planned under stage: <stage>` (set at the brief,
  updated on transition). Because the Critic already gets the full sprint as context,
  it sees the recorded stage without any new summons machinery.

### Consumption (judgment → SKILL.md, Vital Signs)

- The stage is a standing fact of reality about exposure — who suffers when this breaks
  right now — read at every taking of the signs, beside Facts of reality / Things to do /
  Risks.
- The planner weighs it when judging which gates a story needs, how tight "done means"
  should be, `loop:` choices, and what to put before the Critic. There is no table; the
  nature of the project combined with the stage is the manager's call.
- The Critic's charter and summons are unchanged. Its findings are weighed by the
  planner and the operator against the stage — the stage does not build the critique.
- The pre-recap Critic read stays **always** at every stage; waiving it per stage would
  smuggle the rejected posture table in through the back door.

### Transitions (operator seam → SKILL.md Mandate + REFERENCE.md event)

- When the declared stage no longer matches the recorded one, the planner surfaces the
  mismatch at the next gate (brief or recap). The operator decides: forward-only or
  re-baseline.
- The Mandate's named operator seams gain "stage transition".
- The decision is recorded in the event ledger as a sprint-scoped STAGE event —
  `## STAGE — st-YYYYMMDD-<n>` — carrying old stage, new stage, the decision, and its
  rationale. It is a decision record made synchronously at the gate, so it needs no
  RESOLUTION block.

### Lint

New pins in `test/lint-skills.sh` (bash+grep only, per repo convention): the
`Project stage:` declaration line and the four stage names in REFERENCE.md, the Vital
Signs stage prose and the Mandate seam in SKILL.md, the STAGE event heading in
REFERENCE.md.

## What does not change

- `codex/CHARTER.md` and the Critic's disposition — untouched.
- No new mandatory gates, no per-stage behavior anywhere in the skill.
- Execution-layer precision (`EXECUTION.md`, story doc template) — untouched; stage
  rigor reaches executors only through the story docs the planner writes.

## Testing

`test/lint-skills.sh` with the new pins. No script changes, so the per-skill suites are
unaffected.
