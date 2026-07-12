# Interactive story loop and REPLAN handback — design

Date: 2026-07-12
Skills touched: `sprint-orchestrator`, `agent-handoff`
Codex review: 2026-07-12 (sol/xhigh) — findings folded in: claim-branch semantics restored,
event-sourced feedback blocks, publication rule, dossier filename, direction terminal path,
operator-driven planner re-entry.

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
   dossier the next plan session must consume; re-entering planning afterwards is
   operator-driven, in a fresh strongest-model session.

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

Tiers stay orthogonal. In practice S/A stories will almost always read `full`, B stories usually
will too, and C stories usually read `direct`; the guide says so as a tendency, not a rule.

### 2. Execution contract: investigate → brainstorm gate → then autonomous

`agent-handoff/EXECUTION.md` phases for `loop: full`. Branch creation stays in preflight — the
`sprint/NN-*` branch is the story's claim lock (mutual exclusion between sessions), and removing
it would let two sessions duplicate investigation and operator brainstorms:

0. **Preflight** — `git fetch origin`; if `sprint/{NN}-*` exists on any ref the story is taken,
   stop. Create `sprint/{NN}-{slug}` from `origin/main` — at this point it is a **claim branch**:
   it carries no story commits yet. Deploy-project check unchanged.
1. **Investigate** (read-only) — run the story doc's "Start by verifying", reproduce the bug /
   establish the baseline, capture "before" screenshots, restate In/Out of scope.
2. **Brainstorm gate** (`loop: full` only; interactive) — present findings to the operator, weigh
   2–3 approaches with trade-offs and a recommendation. Decisions in the story doc are settled *by
   default*; the operator may amend them live, and amendments are recorded in STORY-FEEDBACK.md.
   Divergences from the doc are handled per §3. This phase is user-gated by design; the
   single-late-checkpoint doctrine (and the "progress pings" mistake) applies only *after* it.
3. **Plan** — write the spec and plan as files on the story branch.
4. **Implement → validate → merge/PR → verify → hand off** — unchanged, autonomous under the
   single late `/goal` checkpoint.

On a clean handback (§3) the executor releases the claim: remove the worktree if one was created,
delete the `sprint/{NN}-*` branch (it has no story commits), and the story reads TODO again.

`loop: direct` skips phase 2: preflight, investigate, then a short TDD plan — unchanged from
today.

Kickoff template changes (`agent-handoff/SKILL.md`, mirrored in `wave-handoffs.sh`):
- Planning-depth line, `full`: "run the contract's investigation + interactive brainstorm phase
  with the operator first". `direct`: unchanged.
- The SETTLED line softens: settled by default; the operator may amend live during the brainstorm;
  amendments land in STORY-FEEDBACK.md.
- `loop: full` requires an interactive session (`codex-app` / `claude-session`) — already true,
  now load-bearing; keep.
- The Hard rules line gains the handback clause: on handback, publish the REPLAN event to trunk
  (docs-only, no trailers) and release the claim branch — so the rule rides the kickoff prompt
  itself, not only EXECUTION.md.

### 3. Divergence protocol: blast-radius analysis, operator-decided handback

When investigation or brainstorm findings diverge from the story doc, the executor applies the
blast-radius test:

- **Contained** to this story's own scope/ownership (e.g. the bug is in Y not X, same fix shape):
  settle inline with the operator, record it in STORY-FEEDBACK.md, proceed.
- **Cross-boundary** — invalidates the premise, reshapes other stories, changes merge order or
  waves, or reveals the story should not exist: present premise, contradicting evidence, and blast
  radius, then ask the operator: **"hand back to sprint-orchestrator now, or continue?"**

On **hand back**, the executor appends an **event block** to STORY-FEEDBACK.md. Events are
immutable and carry an id, so the file is genuinely append-only and repeated REPLANs for the same
story stay distinguishable:

```markdown
## REPLAN — rp-YYYYMMDD-<n> — Story NN
- Premise as written: <quote from the story doc>
- Contradicting evidence: <file/symbol/command anchors>
- Blast radius: <affected stories, dependency edges, waves>
- Recommendation: <one line>
```

**Publication rule** — the event must reach trunk before the session ends, or the next planner
cannot see it (the executor may be in an isolated worktree). Mechanics: commit the append as a
docs-only commit — carrying **no** `Story:`/`Sprint:` trailers; a trailered commit reaching trunk
would flip the handed-back story to DONE — on a `sprint-docs/<event-id>` branch cut from trunk
(not the claim branch, which is about to be deleted). `execution: autonomous` → merge it to trunk
immediately; `stop-at-pr` → open a docs-only PR. Either way, release the claim per §2 and stop:
story reads TODO. The operator re-invokes `/sprint-orchestrator` on the sprint directory.

On **continue**, the operator's decision is recorded in STORY-FEEDBACK.md and the story proceeds
under the amended understanding (the append rides the story's normal commits).

**Planner re-invocation** (extends the existing wave-checkpoint flow in
`sprint-orchestrator/SKILL.md`): on any re-invoke of an existing sprint dir, FIRST scan
STORY-FEEDBACK.md for `## REPLAN` / `## DIRECTION` (§5) event ids with no matching
`## RESOLUTION` block; re-verify each against current source truth; rewrite, cut, or split the
affected story docs; then append the resolution as its own event:

```markdown
## RESOLUTION — rp-YYYYMMDD-<n>
- Resolution: <what changed and why>
```

Unresolved = an event id with no `## RESOLUTION — <id>` block — append-only, bash+grep
detectable, survives sessions, and one rule covers both event types.

`loop: direct` stories hit the same protocol through interrupt #1 (wrong premise). Where an
operator is present, it offers the same hand-back-or-continue choice — the handback *decision*
is always the operator's. On non-interactive transports (`codex exec`, `claude -p`, subagent)
there is no one to ask, so the two cases degenerate to the contract's existing behavior:
a **contained** divergence proceeds under a recorded amendment (no stop); a **cross-boundary**
divergence writes the REPLAN event, publishes it, releases the claim, and stops — stopping is
what interrupt #1 already required; the event is its artifact.

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
- **Publish before firing.** The planner commits and pushes the sprint planning docs (story
  docs, `00-overview.md`, STORY-FEEDBACK.md) to trunk before spawning any subagent — a fresh
  worktree reads planning docs via `git show origin/main:<path>` and cannot see the planner's
  uncommitted files. (This closes a pre-existing hole: pasted cross-session kickoffs have the
  same dependency, it was just never stated.)
- **Same contract, same evidence.** Each subagent receives the story's rendered kickoff prompt
  (same template), runs one story end-to-end in an isolated worktree, and is bound by
  EXECUTION.md unchanged: trailers on every commit, `ownership.owns`/`do_not_touch`, single
  writer per file. `sprint-status.sh` cannot tell the transports apart — state stays git-derived.
- **Scheduling is the plan itself.** Fire only stories whose `depends_on` are DONE and whose
  ownership is disjoint from every in-flight story; hotspot stories run serially in
  `00-overview.md`'s merge order. No new scheduler — the planner wrote these constraints and
  enforces them by choosing what to fire and when.
- **First failure stops the fleet.** A failed story stops further firing; the planner reports
  what ran, what failed, and leaves the failed branch for inspection. No automatic retries.
- **Never for `loop: full`** (those require an interactive session), and a poor fit for
  `frontend: true` stories, whose evidence path ends in Codex.app visual validation anyway;
  backend-mechanical direct stories are the intended case.

### 5. Direction stories — big ambiguous problems become planning input

When planning surfaces a problem too big and unshaped to story-fy, the planner writes a
**direction story** instead of forcing premature stories: `flow: direction`, `loop: full`
(mandatory), typically S-tier. Its deliverable is an investigation dossier — planning input, not
product code.

- **The dossier commit carries the trailers.** The executor writes `dossier-NN.md` into the
  sprint directory and commits it with the story's normal `Story:`/`Sprint:` trailers, merged
  per the sprint's `execution:` mode. DONE derives from the trailers exactly as for any story —
  the convention is simply that the *only* trailered commit a direction story makes is its
  dossier commit. The filename must not match `[0-9]*.md`: `sprint-status.sh` enumerates those
  as stories, and `NN-dossier.md` would surface as a phantom second story `NN`.
- **EXECUTION.md gets an explicit alternate terminal path**, not just "skip prod verification":
  phases 0–2 as any `loop: full` story (claim branch included); then write the dossier on the
  story branch and commit with trailers. No TDD, no tests/typecheck/build gates, no browser
  evidence — the merge gate is that the diff is docs-only. Merge or PR per `execution:` mode;
  the tracker `card.done` intent still fires. Done means: dossier merged, DIRECTION event
  appended, and the operator has read the dossier (the artifact-inspection rule — a dossier is
  an artifact).
- **Skills line: none.** The direction story's brainstorm is the contract's phase-2 gate, not
  `superpowers:brainstorming` — that skill mandates a spec → user review → writing-plans
  lifecycle, which is not the dossier lifecycle. The `flow: direction` mapping lands in
  `agent-handoff/SKILL.md` (the template source of truth) and is mirrored by `wave-handoffs.sh`.
- Alongside the dossier, the executor appends the event (same id scheme as §3):

  ```markdown
  ## DIRECTION — dr-YYYYMMDD-<n> — Story NN
  - Dossier: <path>
  - Recommendation: <one line>
  ```

- **One consumption rule for REPLAN and DIRECTION.** They are the same shape — investigation
  output the next plan session must consume before planning. The §3 sweep reads both event types
  with no matching `## RESOLUTION` block, consumes them (for a dossier: plans the follow-on
  stories or records why not), and appends a `## RESOLUTION — <id>` event for each.
- **Planner re-entry is operator-driven, in a fresh session.** The direction story ends like any
  other: dossier merged, event appended, session stops. The operator then opens a fresh
  strongest-model planner session on the sprint dir. (The skill is manual-only —
  `disable-model-invocation: true` — so a thread could never self-invoke the planner anyway;
  and a just-finished executor sits in a story worktree on a stale branch, the wrong place to
  plan from.) Guardrail: **one planner per sprint dir at a time**; concurrent plan sessions on
  one sprint dir are a planning error (story-number collisions, conflicting merge orders).

### 6. Rendering and tooling

`wave-handoffs.sh`:
- `depth` strings for `full`/`direct` updated to match the new SKILL.md wording.
- SETTLED lines in the rendered kickoff updated to the softened wording.
- `flow: direction` renders no skills line (mirroring the `agent-handoff/SKILL.md` mapping, §5)
  instead of falling through to the TDD default.
- New warning: when rendering a wave, if the sprint's STORY-FEEDBACK.md contains a REPLAN or
  DIRECTION event with no matching RESOLUTION, print a warning to stderr and a line in the
  rendered recap naming the event id and story; rendering proceeds. Warn-not-block is a
  deliberate operator choice — the residual risk is kicking off a story past a known-unresolved
  contradiction, and the recap line is what surfaces it at paste time.
- Known cosmetic limitation, unchanged: the contract path is chosen from `driver_hint`, not the
  paste-time target. Both `~/.claude/skills/...` and `~/.codex/skills/...` resolve to the same
  file on this machine, so a redirected story still reads the correct contract.

### 7. Tests and lints (same commit as the prose they pin)

- `test/lint-skills.sh`:
  - existing pin `contract: first interrupt condition` ("wrong premise") updated if the phrase
    moves; existing `orchestrator: loop field` pin keeps passing.
  - new pins: the `## REPLAN —` / `## DIRECTION —` / `## RESOLUTION —` event heading shapes
    appear in both `EXECUTION.md` and `sprint-orchestrator/SKILL.md`; the planning-depth strings
    in `agent-handoff/SKILL.md` and `wave-handoffs.sh` match; the hand-back-or-continue question
    exists in `EXECUTION.md`; the `direction` flow value appears in the Story Doc Shape and in
    both renderers' mappings; the `dossier-NN.md` naming (never `NN-dossier.md`) is pinned.
- `sprint-orchestrator/test/` gains fixture tests, bash + grep only:
  - a `dossier-NN.md` file in a sprint dir is NOT enumerated as a story by `sprint-status.sh`
    (and a probe documenting that `NN-dossier.md` would be — the regression Codex demonstrated);
  - unresolved-event detection: repeated REPLAN events for one story, interleaved
    REPLAN/DIRECTION/RESOLUTION blocks, resolved vs unresolved;
  - wave-handoffs.sh warning goes to stderr, recap line to stdout (true stream separation);
  - direction stories render with no skills line and no TDD reference.

## Files touched

| File | Change |
|---|---|
| `sprint-orchestrator/SKILL.md` | Plan Session loop guide (§1), consumption sweep + event blocks (§3, §5), contract-line rephrase + subagent execution incl. publish-before-fire (§4), direction stories + `flow: direction` in Story Doc Shape (§5), guardrail rewording |
| `sprint-orchestrator/README.md` | Short updates to match |
| `sprint-orchestrator/wave-handoffs.sh` | Depth strings, SETTLED lines, direction mapping, unresolved-event warning (§6) |
| `agent-handoff/SKILL.md` | Planning-depth line, SETTLED softening (§2), `flow: direction` mapping (§5) |
| `agent-handoff/EXECUTION.md` | Brainstorm gate + claim-branch/handback-release semantics (§2), divergence protocol + publication rule + interrupt #1 (§3), direction-story alternate terminal path (§5) |
| `agent-handoff/README.md` | Short updates to match |
| `test/lint-skills.sh` | Updated + new pins (§7) |
| `sprint-orchestrator/test/` | Dossier-enumeration, event-detection, and rendering fixture tests (§7) |

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
- Warn-not-block on unresolved events (operator's explicit choice): a story can be kicked off
  past a known-unresolved contradiction if the recap warning is ignored.
- The handback publication rule adds git plumbing (`sprint-docs/<event-id>` branch) to a moment
  when the executor is stopping anyway; a session that skips it strands the REPLAN event in a
  doomed worktree. The rendered kickoff must carry the rule, not just EXECUTION.md.
- Two skills and one script share pinned wording; drift is caught by the new lint pins.
