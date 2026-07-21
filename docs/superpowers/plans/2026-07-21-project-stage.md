# Project Stage Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a declared, inherited project stage (`playground | internal | pre-launch | live`) to the sprint orchestrator as manager-judgment context, with transition detection as a named operator seam.

**Architecture:** Judgment-grade prose goes into `sprint-orchestrator/SKILL.md` (Vital Signs + Decision Rights); precision-grade mechanics go into `sprint-orchestrator/REFERENCE.md` (declaration format, discovery order, STAGE event). No per-stage posture table anywhere — the stage is weighed by the planner, never mechanized. Spec: `docs/superpowers/specs/2026-07-21-project-stage-design.md`.

**Tech Stack:** Markdown prose + bash/grep lint (`test/lint-skills.sh`).

## Global Constraints

- Lint pins land **in the same commit** as the prose they pin (repo rule: a passing lint that no longer checks the real string is worse than no lint).
- `has` in `test/lint-skills.sh` uses `grep -qF`: case-sensitive, line-based. Every pinned phrase must appear **on a single line** in the target file — a phrase split across a line break fails.
- Tests are bash + grep only. No YAML parser, no other runtime.
- Run `test/lint-skills.sh` after every task; it must end green. Current baseline: **321 passed, 0 failed**.
- Edits are live: installed skills are symlinks into this repo. No staging copy.
- Do not touch `codex/CHARTER.md`, `EXECUTION.md`, or any script. Prose and lint only.
- TDD order per task: add the failing lint pins first, watch them fail, add the prose, watch them pass.

---

### Task 1: SKILL.md — stage in Vital Signs + operator seam in Decision Rights

**Files:**
- Modify: `sprint-orchestrator/SKILL.md` (Vital Signs section, after the Risks bullet; Decision Rights section, after the capacity bullet)
- Test: `test/lint-skills.sh` (constitution pins block, near the existing `constitution:` pins)

**Interfaces:**
- Consumes: nothing (first task).
- Produces: prose containing the exact single-line phrases the new pins check: `project stage`, `per-stage table:`, `fact of reality about exposure`, `a stage transition —`.

- [ ] **Step 1: Add the failing lint pins**

In `test/lint-skills.sh`, directly after the line `has   "constitution: replan closed by rebuttal" "a rebuttal round on the same" "$ORCH"`, add:

```bash
has   "constitution: stage is a vital sign"  "project stage"           "$ORCH"
has   "constitution: no per-stage table"     "per-stage table:"        "$ORCH"
has   "constitution: stage weighs exposure"  "fact of reality about exposure" "$ORCH"
has   "constitution: stage transition is operator's" "a stage transition —" "$ORCH"
```

- [ ] **Step 2: Run the lint to verify the pins fail**

Run: `test/lint-skills.sh 2>&1 | grep -c '^no'`
Expected: `4` (the four new pins fail; everything else still passes)

- [ ] **Step 3: Add the Vital Signs paragraph**

In `sprint-orchestrator/SKILL.md`, replace:

```markdown
- **Risks** — blast radii, shared-file hotspots, dependency edges, and what is expensive to
  be wrong about.

Stories are the output of holding these three against each other — never the starting
material.
```

with:

```markdown
- **Risks** — blast radii, shared-file hotspots, dependency edges, and what is expensive to
  be wrong about.

One standing attribute rides with the three: the **project stage** — `playground`,
`internal`, `pre-launch`, or `live`, declared once in the project's instructions (format
and discovery in REFERENCE.md). It is a fact of reality about exposure — who suffers when
this breaks right now. Weigh it when you judge which gates a story needs, how tight
"done means" should be, `loop:` choices, and what you put before the Critic. There is no
per-stage table: the nature of the project combined with the stage is your call, and the
pre-recap Critic read stays always at every stage. Record the stage you planned under in
`00-overview.md`; when the declared stage no longer matches, surface the mismatch at the
next gate — forward-only or re-baseline is the operator's call.

Stories are the output of holding these three against each other — never the starting
material.
```

- [ ] **Step 4: Add the operator seam bullet**

In `sprint-orchestrator/SKILL.md`, replace:

```markdown
- capacity — ask how Claude/Codex/Kimi capacity looks right now, record it as plan-time
  context; it informs routing suggestions, never a `driver_hint`;
- a dead transport — takeover and leftover integration require the operator's confirmation
```

with:

```markdown
- capacity — ask how Claude/Codex/Kimi capacity looks right now, record it as plan-time
  context; it informs routing suggestions, never a `driver_hint`;
- a stage transition — when the declared project stage (Vital Signs) no longer matches
  what the sprint was planned under, forward-only or re-baseline is their call, surfaced
  at the next gate;
- a dead transport — takeover and leftover integration require the operator's confirmation
```

- [ ] **Step 5: Run the lint to verify it passes**

Run: `test/lint-skills.sh 2>&1 | tail -1`
Expected: `325 passed, 0 failed`

- [ ] **Step 6: Commit**

```bash
git add sprint-orchestrator/SKILL.md test/lint-skills.sh
git commit -m "sprint-orchestrator: project stage as a Vital Signs attribute + operator seam"
```

---

### Task 2: REFERENCE.md — declaration mechanics + STAGE event

**Files:**
- Modify: `sprint-orchestrator/REFERENCE.md` (Event ledger id-scheme paragraph; after the RETRO block; new section before `## Tracker binding`)
- Test: `test/lint-skills.sh` (reference pins, near the existing `reference:` pins)

**Interfaces:**
- Consumes: Task 1's prose references ("format and discovery in REFERENCE.md", "event format in REFERENCE.md") — this task is what those pointers resolve to.
- Produces: prose containing the exact single-line phrases the new pins check: `Project stage: playground | internal | pre-launch | live`, `Planned under stage:`, `## STAGE — st-`, `st-YYYYMMDD-`.

- [ ] **Step 1: Add the failing lint pins**

In `test/lint-skills.sh`, directly after the line `has   "reference: skipped read never silent" "never as silence"        "$ORCH_REF"`, add:

```bash
has   "reference: project stage declaration" "Project stage: playground | internal | pre-launch | live" "$ORCH_REF"
has   "reference: stage recorded in overview" "Planned under stage:" "$ORCH_REF"
has   "reference: sprint-scoped event ids"  "st-YYYYMMDD-"           "$ORCH_REF"
has   "reference: STAGE event heading"      "## STAGE — st-"         "$ORCH_REF"
```

- [ ] **Step 2: Run the lint to verify the pins fail**

Run: `test/lint-skills.sh 2>&1 | grep -c '^no'`
Expected: `4`

- [ ] **Step 3: Extend the event id-scheme paragraph**

In `sprint-orchestrator/REFERENCE.md`, replace:

```markdown
retro `rt-YYYYMMDD-w<wave>-<n>` — carry the wave number instead: they belong to no single story.
Events already recorded keep their old IDs.
```

with:

```markdown
retro `rt-YYYYMMDD-w<wave>-<n>` — carry the wave number instead: they belong to no single story.
Sprint-scoped events — the STAGE transition record `st-YYYYMMDD-<n>` — carry neither: they
belong to the whole sprint. Events already recorded keep their old IDs.
```

(Must keep the existing substrings `rp-YYYYMMDD-NN-` and `rv-YYYYMMDD-w` intact — two older pins check them.)

- [ ] **Step 4: Add the STAGE event block**

In `sprint-orchestrator/REFERENCE.md`, directly after the RETRO block (the block ending in `- Report: <path to the reviewer's full output>`) and before `### The unresolved-event sweep`, insert:

```markdown
STAGE (the declared project stage changed mid-program; decided by the operator at the gate,
so it is a decision record — it needs no RESOLUTION block):

    ## STAGE — st-YYYYMMDD-<n>
    - Was: <stage recorded in 00-overview.md>
    - Now: <declared stage>
    - Decision: forward-only | re-baseline
    - Rationale: <one line>
```

Do not add STAGE to the unresolved-event sweep list — the sweep covers events awaiting a response; a STAGE event is resolved the moment it is written.

- [ ] **Step 5: Add the Project stage section**

In `sprint-orchestrator/REFERENCE.md`, directly before `## Tracker binding`, insert:

```markdown
## Project stage

The project's exposure stage is declared once, in one line:

    Project stage: playground | internal | pre-launch | live

Discovery order mirrors the tracker binding: a path named by the operator, then the
project's `AGENTS.md`, then its `CLAUDE.md`. If nothing is declared, ask once at the brief
gate and offer to write the line; if the operator declines, record the working assumption
in `00-overview.md` and proceed — the stage is mentioned once, never nagged.

Record the stage in `00-overview.md` as `Planned under stage: <stage>` — set at the brief,
updated on transition. The Critic sees it there as part of the full-sprint context; no
summons machinery carries it.
```

- [ ] **Step 6: Run the lint to verify it passes**

Run: `test/lint-skills.sh 2>&1 | tail -1`
Expected: `329 passed, 0 failed`

- [ ] **Step 7: Commit**

```bash
git add sprint-orchestrator/REFERENCE.md test/lint-skills.sh
git commit -m "sprint-orchestrator: project stage declaration + STAGE event mechanics"
```

---

## Self-Review notes (already run by the planner)

- **Spec coverage:** declaration → Task 2 Step 5; consumption via Vital Signs → Task 1 Step 3; operator seam → Task 1 Step 4; STAGE event → Task 2 Steps 3–4; lint → both tasks; "no posture table / critic charter untouched / no new gates" → enforced by Global Constraints and by the absence of any task touching them.
- **Placeholders:** none — every edit is quoted in full.
- **Line-based lint check:** every pinned phrase was verified to sit on a single line in the quoted prose (`per-stage table:` begins its line; `a stage transition —` begins its line; the declaration line is a single code-block line).
