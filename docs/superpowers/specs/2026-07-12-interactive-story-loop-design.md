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

Two adjacent gaps surfaced in the same runs. A plan session that sees one big unshaped problem
plus several small mechanical ones has no artifact for the big one (stubs assume the work is
merely blocked, not unshaped) and no sanctioned way to just run the small ones itself. And any
in-session execution must not undercut cross-harness distribution — when Claude capacity is
tight, the same stories must still print as Codex handoffs.

## Goals

1. `loop: full` stories open with focused investigation plus an **interactive brainstorm with the
   operator** before any implementation.
2. A structured, session-surviving **handback** to the sprint planner when findings diverge beyond
   the story's own boundary — offered to the operator, never automatic.
3. Practical guidance (examples, not rules) for when the planner should set `full` vs `direct`.
4. The plan session may execute approved `loop: direct` stories itself via subagents — same
   execution contract, chosen at handoff time so cross-harness prints stay first-class.
5. A **direction story** flavor for big ambiguous problems: the deliverable is an investigation
   dossier the next plan session must consume, and the direction thread may itself re-enter
   sprint planning.

## Non-goals

- No change to commit trailers, story-state derivation, `sprint-status.sh`, the tier ladder,
  driver routing, or tracker binding.
- No new frontmatter keys (`flow:` gains a `direction` value); the only new sprint-dir file is a
  direction story's dossier.
- No change to `loop: direct` execution semantics beyond the shared divergence protocol and the
  optional subagent transport.

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

…then stops cleanly: no branch, no story commits, story stays TODO. The operator re-invokes
`/sprint-orchestrator` on the sprint directory. If the append itself is committed, the commit
carries **no** `Story:`/`Sprint:` trailers — a trailered commit reaching trunk would flip the
handed-back story to DONE.

On **continue**, the operator's decision is recorded in STORY-FEEDBACK.md and the story proceeds
under the amended understanding.

**Planner re-invocation** (extends the existing wave-checkpoint flow in
`sprint-orchestrator/SKILL.md`): on any re-invoke of an existing sprint dir, FIRST scan
STORY-FEEDBACK.md for `## REPLAN` blocks lacking a `- Resolution:` line; re-verify each against
current source truth; rewrite, cut, or split the affected story docs; append `- Resolution:
<what changed>` under the block. Unresolved = block without a Resolution line — append-only,
bash+grep detectable, survives sessions. (§5 generalizes this sweep to `## DIRECTION` blocks with
one shared rule.)

`loop: direct` stories hit the same protocol through interrupt #1 (wrong premise): it now offers
the same hand-back-or-continue choice, and the REPLAN block is the artifact when the operator
chooses handback. On non-interactive transports (`codex exec`, `claude -p`, subagent) there is no
one to ask: write the REPLAN block and stop — stopping is what interrupt #1 already required.

### 4. Planner-fired subagent execution for `loop: direct` stories

After the plan-session recap is presented and **the user approves**, the planner may execute
`loop: direct` stories itself by spawning subagents — instead of, not in addition to, printing
their handoff prompts. The gate matters: today's contract line "it plans and hands off; it does
not implement" exists so a bad plan is seen before it runs. The line is rephrased, not dropped:
the plan session executes in-session only via subagents, only for `loop: direct` stories, and
only after the user approves the recap.

- **Transport stays handoff-time resolved** (capability → the user's explicit say → current
  availability → affinity). "Fire as my subagents" is one more answer to the capacity question
  the planner already asks at recap. When Claude capacity is tight, the same stories render as
  `codex exec` prints exactly as today — the rendered handoff remains the universal transport,
  and nothing at plan time (frontmatter, `driver_hint`) encodes the choice.
- **Same contract, same evidence.** Each subagent receives the story's rendered kickoff prompt
  (same template), runs in an isolated worktree, and is bound by EXECUTION.md: trailers on every
  commit, `ownership.owns`/`do_not_touch`, single writer per file. Hotspot stories run serially
  per `00-overview.md`'s merge order. `sprint-status.sh` cannot tell the transports apart —
  state stays git-derived.
- **Never for `loop: full`** (those require an interactive session), and a poor fit for
  `frontend: true` stories, whose evidence path ends in Codex.app visual validation anyway;
  backend-mechanical direct stories are the intended case.

### 5. Direction stories — big ambiguous problems become planning input

When planning surfaces a problem too big and unshaped to story-fy, the planner writes a
**direction story** instead of forcing premature stories: `flow: direction`, `loop: full`
(mandatory), typically S-tier. Its deliverable is an investigation dossier — planning input, not
product code.

- **Dossier as the DONE signal.** The executor writes `NN-dossier.md` into the sprint directory
  and commits it with the story's normal `Story:`/`Sprint:` trailers, merged per the sprint's
  `execution:` mode. The story reads DONE from git like any other; no special casing in
  `sprint-status.sh`.
- **EXECUTION.md gets a short "Direction stories" subsection:** same preflight → investigate →
  brainstorm phases as any `loop: full` story; then write the dossier, commit with trailers,
  merge; skip prod verification; append to STORY-FEEDBACK.md:

  ```markdown
  ## DIRECTION — Story NN
  - Dossier: <path>
  - Recommendation: <one line>
  ```

- **One consumption rule for REPLAN and DIRECTION.** They are the same shape — investigation
  output the next plan session must consume before planning. The planner re-invocation sweep
  (§3) reads both block types lacking a `- Resolution:` line, consumes them (for a dossier:
  plans the follow-on stories or records why not), and appends `- Resolution:` under each.
- **Planner re-entry.** The direction thread may itself re-invoke `/sprint-orchestrator` on the
  same sprint dir once its dossier is merged — the strongest-model rule holds because direction
  stories run on the top tier. Guardrail: **one planner per sprint dir at a time**; the thread
  re-enters planning only after its investigation is done, and concurrent plan sessions on one
  sprint dir are a planning error (story-number collisions, conflicting merge orders).

### 6. Rendering and tooling

`wave-handoffs.sh`:
- `depth` strings for `full`/`direct` updated to match the new SKILL.md wording.
- SETTLED lines in the rendered kickoff updated to the softened wording.
- `flow: direction` gets its own skills line (`superpowers:brainstorming`, no TDD) instead of
  falling through to the TDD default.
- New warning: when rendering a wave, if the sprint's STORY-FEEDBACK.md contains an unresolved
  REPLAN or DIRECTION block, print a warning to stderr and a line in the rendered recap naming
  the story; rendering proceeds (warn, not block).

### 7. Tests and lints (same commit as the prose they pin)

- `test/lint-skills.sh`:
  - existing pin `contract: first interrupt condition` ("wrong premise") updated if the phrase
    moves; existing `orchestrator: loop field` pin keeps passing.
  - new pins: the `## REPLAN — Story` and `## DIRECTION — Story` heading shapes appear in both
    `EXECUTION.md` and `sprint-orchestrator/SKILL.md`; the planning-depth strings in
    `agent-handoff/SKILL.md` and `wave-handoffs.sh` match; the hand-back-or-continue question
    exists in `EXECUTION.md`; the `direction` flow value appears in the Story Doc Shape.
- `sprint-orchestrator/test/` gains a fixture test for the wave-handoffs.sh warning
  (unresolved REPLAN/DIRECTION block → warning emitted; resolved block → silent). Bash + grep
  only.

## Files touched

| File | Change |
|---|---|
| `sprint-orchestrator/SKILL.md` | Plan Session loop guide (§1), consumption sweep (§3, §5), contract-line rephrase + subagent execution (§4), direction stories + `flow: direction` in Story Doc Shape (§5), guardrail rewording |
| `sprint-orchestrator/README.md` | Short updates to match |
| `sprint-orchestrator/wave-handoffs.sh` | Depth strings, SETTLED lines, direction skills line, REPLAN/DIRECTION warning (§6) |
| `agent-handoff/SKILL.md` | Planning-depth line, SETTLED softening (§2) |
| `agent-handoff/EXECUTION.md` | Phase reorder, brainstorm gate (§2), divergence protocol + interrupt #1 (§3), direction-story subsection (§5) |
| `agent-handoff/README.md` | Short updates to match |
| `test/lint-skills.sh` | Updated + new pins (§7) |
| `sprint-orchestrator/test/` | REPLAN/DIRECTION warning fixture test (§7) |

## Risks

- Prose-only enforcement: the brainstorm gate binds through the kickoff prompt and EXECUTION.md;
  a model that ignored "self-directed brainstorm" could ignore this too. Mitigation: the gate is
  now interactive — its absence is visible to the operator immediately, unlike the silent
  self-directed collapse it replaces.
- Planner-fired subagents concentrate plan and execution in one session. Mitigations: the recap
  approval gate sits between them, and state stays git-derived, so a misbehaving run is fully
  auditable from trailers and branches.
- "One planner per sprint dir at a time" is a prose rule with no tooling enforcement; a
  violation shows up as story-number collisions in `00-overview.md` review, not before.
- Two skills and one script share pinned wording; drift is caught by the new lint pins.
