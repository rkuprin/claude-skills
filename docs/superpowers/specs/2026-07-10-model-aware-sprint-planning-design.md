# Model-Aware Sprint Planning + Unified Agent Handoff — Design

- **Date:** 2026-07-10
- **Repo:** `~/claude-skills` (shared skills, symlinked into `~/.claude/skills` and `~/.codex/skills`)
- **Status:** draft for review

## Context

Two paired skills exist today: `sprint-orchestrator` (manual, human-initiated sprint planner that
writes story docs) and `codex-execution-handoff` (renders a ~50-line kickoff prompt that runs one
story's full lifecycle in Codex.app). Multiple driver models are in play — Claude Code runs Fable or
Opus, Codex runs Sol (ultra effort available since codex-cli 0.144) — and their subscriptions deplete
independently, so which agent should take which work changes mid-sprint.

Problems this design addresses:

1. Planning is not model/harness-aware: nothing says which model should plan, which driver suits
   which story, or how to react when one subscription is depleted.
2. Handoff is story-shaped only. There is no anytime handoff — e.g., mid-story, Claude implemented a
   design and needs Codex.app to visually validate it (only the app renders screenshots inline).
3. Two handoff skills would misroute ("I call agent-handoff but need execution handoff"), so the
   handoff surface must be one skill.
4. The kickoff prompt is heavy. Execution mechanics belong in a doc the executor reads; the pasted
   prompt should be lean.

## Decisions locked during brainstorm

- **Late driver binding.** The planner records a per-story driver *hint* derived from the work's
  nature; the final driver is resolved at handoff time against capacity at that moment. A capacity
  flip never invalidates the plan.
- **One handoff skill.** New `agent-handoff` with three modes; `codex-execution-handoff` is deleted
  (content folds in; git history keeps the prose).
- **No driver registry.** Model personalities are a one-two line heuristic inside the skill; the
  judgment stays with the running model and the user. No model catalog to maintain.
- **Playbook doc.** The lifecycle contract moves to `agent-handoff/EXECUTION.md` (same pattern as the
  `/codex` skill's `CHARTER.md`: doc carries disposition, prompt carries transport). The pasted
  prompt keeps a one-line hard-rules block because a pasted prompt is obeyed more reliably than a
  referenced doc — only the catastrophic-if-missed rules stay inline.

## sprint-orchestrator changes

All additive prose + frontmatter; state derivation (`sprint-status.sh`, trailers) is untouched.

1. **Planner model gate** (new ~3-line section). Sprint planning runs on the most capable model
   available. At session start the planner names the model it is running as; if that is not the
   strongest tier reachable right now (today: Fable, else Opus, on Claude Code; Sol at ultra effort
   on Codex), it says so and offers to stop so the user can relaunch. No hard block.
2. **Planning philosophy** (new paragraph in Plan Session). This skill does high-level planning
   backed by in-depth research; it does not write per-story implementation plans. Default: each
   story runs its own brainstorm → spec → plan → execute loop inside its execution session. A story
   simple enough to fully define at plan time is marked `loop: direct` and delegated one-shot
   (subagent, `codex exec`, or `claude -p`).
3. **Driver awareness** (two-line heuristic, verbatim spirit): *Codex leans mechanistic, devops, and
   browser-driving work; Claude leans creative, frontend-heavy, ambiguous work. Frontend visual
   validation renders only in Codex.app.* Anything past that is the planning model's judgment.
4. **Capacity step** (Plan Session, before recap). Ask the user how Claude/Codex capacity looks
   right now; weight driver hints accordingly; note the answer in `00-overview.md` as plan-time
   context. Informational only — routing is re-decided at handoff time.
5. **Kickoff line** in the story-doc template points at `agent-handoff` (story-execution mode for
   `loop: full`, task mode for `loop: direct`) instead of `codex-execution-handoff`.
6. **"Integration Is Planned Here, Performed Elsewhere"** section names `agent-handoff` as the
   performer.

Story frontmatter delta (three new fields; all existing fields unchanged):

```yaml
loop: full            # full | direct — full: story runs its own brainstorm→spec→plan→execute loop
driver_hint: codex    # codex | claude | either — recommendation only, resolved at handoff time
driver_why: one line tying the hint to the work's nature
```

## agent-handoff (new skill)

Model-invocable (no `disable-model-invocation`; no `agents/openai.yaml` guard) — mid-story sessions
must be able to invoke it, and the user can call it explicitly anytime. It renders text to paste; it
never executes the work itself.

**Prompt shape, all modes** (the short-prompt contract):

```
<Title — becomes the receiving session's name>

Read the task file: <path>
Use skills: <skill names to invoke on the other side — Claude Code and Codex share the skills repo>
<2-3 lines of live context>

/goal <observable done — almost always present>
```

**Task file.** Written to `~/.handoffs/YYYY-MM-DD-<slug>.md` — outside any git worktree (worktrees
are deleted long before review, same rationale as `~/.sprint-evidence`) — unless an existing doc
(story doc, spec) already covers the task, in which case point at that. Contents: the task, current
state, relevant paths/symbols/anchors, constraints.

**Target selection.** `codex-app | codex-cli | claude-cli | claude-session`, picked from the task's
nature plus the user's stated capacity; the skill states which target it picked and why in one line.
Anything needing rendered screenshots must target `codex-app`.

### Mode: task (default)

Bounded work, result returned to the caller — a report, a fixed config, a research answer. No
lifecycle machinery: no trailers, no merge order, no deploy gates.

### Mode: visual-validation (flagship)

For "implemented here, confirm it there". Task file lists changed surfaces as `(route, state)` plus
what correct looks like. The prompt instructs the receiving Codex.app session to drive the flows,
fix small defects in place (or report if not small), and **end its reply with the test scenario
(steps, expected vs observed) and inline screenshots grouped per surface — written for the user, not
for another agent.** Each shot names its driver and viewport (one line; no heavy provenance table).
Codex.app only; the skill states plainly that the CLI cannot render images.

### Mode: story-execution

Input: a planned story doc (typically from `sprint-orchestrator`). Renders the lean kickoff prompt:

```
Story {NN}: {Three Descriptive Words}

You are executing ONE story end-to-end.
Read first: {STORY_DOC}, 00-overview.md, STORY-FEEDBACK.md, and repo conventions (AGENTS.md / CLAUDE.md).
Execution contract: ~/.codex/skills/agent-handoff/EXECUTION.md — follow it exactly.
Hard rules: every commit carries the Story:/Sprint: trailers; never `git checkout main`; if
sprint/{NN}-* already exists on any ref the story is taken — stop; never leave prod broken.

/goal {STORY_GOAL}
```

`execution: autonomous | stop-at-pr` comes from the story doc as today. The contract path is spelled
for the target harness (`~/.codex/skills/...` for Codex, `~/.claude/skills/...` for Claude).

## EXECUTION.md (new, beside the skill)

The lifecycle contract migrated from today's `codex-execution-handoff` prompt template and prose,
addressed to the executing agent:

- Preflight: fetch; refuse an existing `sprint/NN-*` branch; `git switch -c` off `origin/main`;
  never `git checkout main`; deploy-project link check.
- Plan: own approach; do the doc's "Start by verifying"; baseline + "before" screenshots first.
- Implement: TDD; stay inside `ownership.owns`; trailers on every commit.
- Validate locally: tests + typecheck; drive Browser Verification; "after" screenshots; open artifacts.
- Merge & deploy: gate on tests + typecheck + production build + both trailers; overview's merge
  order; rebase-once-retry-once on rejected push; deploy with the project's command.
- Verify on prod: drive verification on the live URL; roll back or revert if not a fast fix; never
  leave prod broken.
- Hand off: STORY-FEEDBACK.md append; "How to test this yourself" format (what changed · live URL +
  role · exact steps, expected vs observed · test data · evidence · risk + rollback · checks run ·
  open questions); tracker card via `add_comment`.
- Evidence rules: `surfaces:` is a floor; before/after locally + after on prod per `(route, state)`;
  approved drivers only (named in the project's AGENTS.md); provenance per shot; files under
  `~/.sprint-evidence/{SPRINT}/{NN}-{SLUG}/`, never `/tmp`, never inside a worktree; screenshots
  inline in the final Codex.app message.
- `stop-at-pr` collapse: open a PR, do not merge, do not deploy; trailers still on; `DONE` flips when
  the human merges.
- Common mistakes (migrated list).
- The three legitimate early interrupts: wrong premise / genuine product ambiguity; cannot keep prod
  green; no approved driver can drive the browser verification.

## Deletion

`codex-execution-handoff/` is removed from the repo, and its symlinks are removed from
`~/.claude/skills` and `~/.codex/skills`. All references move to `agent-handoff`
(`sprint-orchestrator/SKILL.md`, both READMEs, `test/lint-skills.sh`). Git history keeps the prose.

## Lint changes (`test/lint-skills.sh`)

- Orchestrator additions: `has driver_hint:`, `has loop:`, `has driver_why:`; existing checks stay.
- The codex-execution-handoff block is replaced by agent-handoff checks split across the two files:
  - `SKILL.md`: is model-invocable (`hasnt disable-model-invocation`); names `Codex.app` for
    visual-validation; `/goal` present; hard-rules line names both trailers and negated
    `git checkout main`; `~/.handoffs` named; names both harness forms of the contract path
    (`~/.codex/skills/...` and `~/.claude/skills/...`); no lifecycle machinery leaking into task /
    visual-validation modes.
  - `EXECUTION.md`: both trailers; `git checkout main` only ever negated; `git switch -c`; refuses a
    taken story; approved-driver rule; DOM-check ban; `.sprint-evidence` path; all three interrupt
    conditions; stop-at-pr collapse.

## READMEs

- Repo `README.md`: skill list gains agent-handoff, drops codex-execution-handoff.
- `agent-handoff/README.md`: what it is (prompt renderer, three modes), prerequisites (Codex.app for
  anything visual), use examples.
- `sprint-orchestrator/README.md` + `SKILL.md`: pairing note points at agent-handoff.

## Non-goals

- No driver registry or model catalog; no automation of capacity detection (it is a question to the
  user).
- No changes to `sprint-status.sh`, the trailer convention, or story state derivation.
- No changes to the `/codex` reviewer skill.

## Risks

- **Referenced-doc adherence.** A doc is followed less reliably than a pasted prompt. Mitigation:
  the inline hard-rules line carries the four catastrophic rules; everything else in EXECUTION.md is
  recoverable if skimmed.
- **Model-invocation misfire.** agent-handoff becomes invocable; a vague description could trigger
  it spuriously. Mitigation: description names concrete triggers (hand off, delegate, visual
  validation, kickoff a story) and the skill's first step is confirming there is a bounded task and
  a goal.
- **Harness path drift.** The EXECUTION.md path differs per harness; the renderer must emit the path
  matching the target, and the lint checks the template names both forms.

## Success criteria

- `test/lint-skills.sh` and `sprint-orchestrator/test/test-sprint-status.sh` pass.
- `codex-execution-handoff` gone from repo and both skills dirs; `agent-handoff` linked in both.
- A planned story renders a lean kickoff prompt (story-execution mode) whose contract lives in
  EXECUTION.md; a `loop: direct` story renders a task-mode prompt.
- The visual-validation template ends with inline screenshots + a test scenario addressed to the
  user.
