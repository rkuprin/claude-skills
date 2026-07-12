# Interactive story loop and REPLAN handback — design

Date: 2026-07-12
Skills touched: `sprint-orchestrator`, `agent-handoff`

## Problem

Ten sprint runs across models show story execution is "just go and do": the planner writes
complete-looking story docs, the kickoff prompt declares decisions SETTLED, and `loop: full`'s
"self-directed brainstorm" — explicitly not user-gated, with no artifact gate — quietly collapses
to zero. That is right for simple, well-trodden stories, wrong for the rest: those should open
with focused investigation and a real brainstorm with the operator. And when investigation
contradicts a story's premise, there is no return path to the planner — interrupt #1 stops and
asks the user inline, the planner only reconvenes at wave boundaries, and nothing is written that
a later plan session must consume.

## Goals

1. `loop: full` stories open with focused investigation plus an **interactive brainstorm with the
   operator** before any implementation.
2. A structured, session-surviving **handback** to the sprint planner when findings diverge beyond
   the story's own boundary — offered to the operator, never automatic.
3. Practical guidance (examples, not rules) for when the planner should set `full` vs `direct`.

## Non-goals

- No change to commit trailers, story-state derivation, `sprint-status.sh`, the tier ladder,
  driver routing, or tracker binding.
- No new files in the sprint directory; no new frontmatter keys.
- No change to `loop: direct` execution beyond the shared divergence protocol.

## Design

### 1. `loop:` is planner judgment, guided by examples

`loop: full | direct` keeps its slot; its *meaning* changes on the `full` side (§2). No tier→loop
rule, no `loop_why:` key. The planner sets it per story by judgment and may simply ask the user
during the plan session when unsure.

`sprint-orchestrator/SKILL.md`'s Plan Session section replaces the current `loop:` definitions
with a short practical guide:

**Brainstorm (`loop: full`) when:**
- the design space is open — multiple valid approaches with genuinely different trade-offs
  (e.g. "add caching to report generation": cache layer? precompute? change the query?);
- investigation could plausibly reshape the approach — novel integration, unfamiliar subsystem,
  a premise the plan session could only verify shallowly;
- user-facing design judgment is involved — layout, flow, wording a spec cannot settle.

**Go direct (`loop: direct`) when:**
- the work repeats a well-trodden in-repo pattern (another CRUD endpoint shaped like the last three);
- it is a mechanical sweep, rename, or config change;
- it is a bugfix where the plan session already found root cause and the fix shape is obvious;
- the plan session already verified everything the executor would otherwise investigate.

Tiers stay orthogonal. In practice S/A stories will almost always read `full` and C stories
`direct`; the guide says so as a tendency, not a rule.

### 2. Execution contract: investigate → brainstorm gate → then autonomous

`agent-handoff/EXECUTION.md` phases are reordered for `loop: full`; branch creation moves after
the brainstorm:

0. **Preflight** — `git fetch origin`; if `sprint/{NN}-*` exists on any ref the story is taken,
   stop. Deploy-project check unchanged. **No branch is created here.**
1. **Investigate** (read-only) — run the story doc's "Start by verifying", reproduce the bug /
   establish the baseline, capture "before" screenshots, restate In/Out of scope.
2. **Brainstorm gate** (`loop: full` only; interactive) — present findings to the operator, weigh
   2–3 approaches with trade-offs and a recommendation. Decisions in the story doc are settled *by
   default*; the operator may amend them live, and amendments are recorded in STORY-FEEDBACK.md.
   Divergences from the doc are handled per §3. This phase is user-gated by design; the
   single-late-checkpoint doctrine (and the "progress pings" mistake) applies only *after* it.
3. **Branch + plan** — create `sprint/{NN}-{slug}` from `origin/main`, write the spec and plan as
   files on the story branch.
4. **Implement → validate → merge/PR → verify → hand off** — unchanged, autonomous under the
   single late `/goal` checkpoint.

`loop: direct` skips phase 2: investigate, then a short TDD plan, as today. Branch creation is
late for both loop values — one contract, and a story stopped during investigation never leaves a
DOING branch behind.

Kickoff template changes (`agent-handoff/SKILL.md`, mirrored in `wave-handoffs.sh`):
- Planning-depth line, `full`: "run the contract's investigation + interactive brainstorm phase
  with the operator first". `direct`: unchanged.
- The SETTLED line softens: settled by default; the operator may amend live during the brainstorm;
  amendments land in STORY-FEEDBACK.md.
- `loop: full` requires an interactive session (`codex-app` / `claude-session`) — already true,
  now load-bearing; keep.

### 3. Divergence protocol: blast-radius analysis, operator-decided handback

When investigation or brainstorm findings diverge from the story doc, the executor applies the
blast-radius test:

- **Contained** to this story's own scope/ownership (e.g. the bug is in Y not X, same fix shape):
  settle inline with the operator, record it in STORY-FEEDBACK.md, proceed.
- **Cross-boundary** — invalidates the premise, reshapes other stories, changes merge order or
  waves, or reveals the story should not exist: present premise, contradicting evidence, and blast
  radius, then ask the operator: **"hand back to sprint-orchestrator now, or continue?"**

On **hand back**, the executor appends to STORY-FEEDBACK.md:

```markdown
## REPLAN — Story NN
- Premise as written: <quote from the story doc>
- Contradicting evidence: <file/symbol/command anchors>
- Blast radius: <affected stories, dependency edges, waves>
- Recommendation: <one line>
```

…then stops cleanly: no branch, no commits, story stays TODO. The operator re-invokes
`/sprint-orchestrator` on the sprint directory.

On **continue**, the operator's decision is recorded in STORY-FEEDBACK.md and the story proceeds
under the amended understanding.

**Planner re-invocation** (extends the existing wave-checkpoint flow in
`sprint-orchestrator/SKILL.md`): on any re-invoke of an existing sprint dir, FIRST scan
STORY-FEEDBACK.md for `## REPLAN` blocks lacking a `- Resolution:` line; re-verify each against
current source truth; rewrite, cut, or split the affected story docs; append `- Resolution:
<what changed>` under the block. Unresolved = block without a Resolution line — append-only,
bash+grep detectable, survives sessions.

`loop: direct` stories hit the same protocol through interrupt #1 (wrong premise): it now offers
the same hand-back-or-continue choice, and the REPLAN block is the artifact when the operator
chooses handback. On non-interactive transports (`codex exec`, `claude -p`, subagent) there is no
one to ask: write the REPLAN block and stop — stopping is what interrupt #1 already required.

### 4. Rendering and tooling

`wave-handoffs.sh`:
- `depth` strings for `full`/`direct` updated to match the new SKILL.md wording.
- SETTLED lines in the rendered kickoff updated to the softened wording.
- New warning: when rendering a wave, if the sprint's STORY-FEEDBACK.md contains an unresolved
  REPLAN block, print a warning to stderr and a line in the rendered recap naming the story;
  rendering proceeds (warn, not block).

### 5. Tests and lints (same commit as the prose they pin)

- `test/lint-skills.sh`:
  - existing pin `contract: first interrupt condition` ("wrong premise") updated if the phrase
    moves; existing `orchestrator: loop field` pin keeps passing.
  - new pins: the `## REPLAN — Story` heading shape appears in both `EXECUTION.md` and
    `sprint-orchestrator/SKILL.md`; the planning-depth strings in `agent-handoff/SKILL.md` and
    `wave-handoffs.sh` match; the hand-back-or-continue question exists in `EXECUTION.md`.
- `sprint-orchestrator/test/` gains a fixture test for the wave-handoffs.sh REPLAN warning
  (unresolved block → warning emitted; resolved block → silent). Bash + grep only.

## Files touched

| File | Change |
|---|---|
| `sprint-orchestrator/SKILL.md` | Plan Session loop guide (§1), re-invocation reads REPLAN first (§3), guardrail rewording |
| `sprint-orchestrator/README.md` | Short updates to match |
| `sprint-orchestrator/wave-handoffs.sh` | Depth strings, SETTLED lines, REPLAN warning (§4) |
| `agent-handoff/SKILL.md` | Planning-depth line, SETTLED softening (§2) |
| `agent-handoff/EXECUTION.md` | Phase reorder, brainstorm gate (§2), divergence protocol + interrupt #1 (§3) |
| `agent-handoff/README.md` | Short updates to match |
| `test/lint-skills.sh` | Updated + new pins (§5) |
| `sprint-orchestrator/test/` | REPLAN warning fixture test (§5) |

## Risks

- Prose-only enforcement: the brainstorm gate binds through the kickoff prompt and EXECUTION.md;
  a model that ignored "self-directed brainstorm" could ignore this too. Mitigation: the gate is
  now interactive — its absence is visible to the operator immediately, unlike the silent
  self-directed collapse it replaces.
- Two skills and one script share pinned wording; drift is caught by the new lint pins.
