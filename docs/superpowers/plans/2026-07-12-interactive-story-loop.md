# Interactive Story Loop and Feedback Events Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `loop: full` stories open with investigation + an interactive operator brainstorm, add REPLAN/DIRECTION feedback events with an operator-decided handback, sanction planner-fired subagent execution for approved `loop: direct` stories, and add direction stories — per the spec at `docs/superpowers/specs/2026-07-12-interactive-story-loop-design.md`.

**Architecture:** This repo's product is prose: two skill files (`sprint-orchestrator/SKILL.md`, `agent-handoff/SKILL.md`), one execution contract (`agent-handoff/EXECUTION.md`), one renderer (`sprint-orchestrator/wave-handoffs.sh`) that mirrors the SKILL.md template, and bash+grep tests that pin the load-bearing strings. Every task pairs a prose/script change with the lint pins or fixture assertions that pin it, in the same commit.

**Tech Stack:** Markdown prose, bash, grep/awk/sed. No YAML parser, no other runtime.

## Global Constraints

- All tests are bash + grep only (repo rule in `CLAUDE.md`). No new runtimes.
- When pinned prose changes, `test/lint-skills.sh` updates in the SAME commit (repo rule).
- Never write `git checkout main` un-negated — the lint rejects it in the agent-handoff files.
- Conventional commits: `type(scope): description`, imperative, under 72 chars.
- Stage explicit paths, never `git add -A`. Check `git branch --show-current` + `git status --short` in the same command as any commit.
- Edits are live deploys: installed skills symlink into this repo. Run the relevant test script after every task.
- These exact strings are shared across files and must match byte-for-byte wherever they appear:
  - Depth line (full): `run the contract's investigation + interactive brainstorm phase with the operator first`
  - Depth line (direct): `the story is fully defined — go straight to a short TDD plan`
  - Event headings: `## REPLAN — rp-YYYYMMDD-<n> — Story {NN}`, `## DIRECTION — dr-YYYYMMDD-<n> — Story {NN}`, `## RESOLUTION — <id>` (RESOLUTION events are written only by the planner, so the RESOLUTION heading is pinned in `sprint-orchestrator/SKILL.md` only — a deliberate narrowing of spec §7, which loosely says "both files")
  - Dossier filename: `dossier-{NN}.md` (concrete form `dossier-NN.md`); never `{NN}-dossier.md`
- Working branch: create `feat/interactive-story-loop` from the current `main` before Task 1; all commits land there.

---

### Task 1: EXECUTION.md — phases, divergence protocol, direction stories

**Files:**
- Modify: `agent-handoff/EXECUTION.md` (full-content replacement)
- Modify: `test/lint-skills.sh` (add pins in the `--- agent-handoff (EXECUTION.md...) ---` section, after line 118)

**Interfaces:**
- Produces: the exact strings later tasks reference — the two depth lines, the three event headings, `hand back to sprint-orchestrator now, or continue?`, `settled by default`, `dossier-{NN}.md`, `Release the claim`, `publish the REPLAN event`. Task 2's SKILL.md and Task 4's renderer must copy these verbatim.
- Consumes: nothing.

- [ ] **Step 1: Create the working branch**

```bash
cd ~/claude-skills && git branch --show-current && git status --short && git switch -c feat/interactive-story-loop main
```

- [ ] **Step 2: Add the failing lint pins**

In `test/lint-skills.sh`, insert after the existing `contract: git checkout main only ever negated` check (currently line 118), before the `# --- claude-reviewer ---` section:

```bash
has   "contract: brainstorm gate section"    "## 2. Brainstorm gate" "$AHEXEC"
has   "contract: settled by default"         "settled by default" "$AHEXEC"
hasnt "contract: no hard SETTLED wording"    "are SETTLED"        "$AHEXEC"
has   "contract: hand-back-or-continue question" "hand back to sprint-orchestrator now, or continue?" "$AHEXEC"
has   "contract: REPLAN event heading"       "## REPLAN — rp-"    "$AHEXEC"
has   "contract: DIRECTION event heading"    "## DIRECTION — dr-" "$AHEXEC"
has   "contract: events publish without trailers" 'NO `Story:`/`Sprint:` trailers' "$AHEXEC"
has   "contract: claim released on handback" "Release the claim"  "$AHEXEC"
has   "contract: direction stories section"  "## Direction stories" "$AHEXEC"
has   "contract: dossier naming"             "dossier-{NN}.md"    "$AHEXEC"
```

- [ ] **Step 3: Run lint to verify the new pins fail**

Run: `test/lint-skills.sh | grep FAIL`
Expected: exactly the 10 new pins FAIL (9 `has` missing + 1 `hasnt` found: `are SETTLED` exists at EXECUTION.md line 5 today); every pre-existing check still passes.

- [ ] **Step 4: Replace EXECUTION.md with the new contract**

Write this complete content to `agent-handoff/EXECUTION.md` (the Evidence and Hand off sections are carried over unchanged except step renumbering):

````markdown
# Execution contract — one sprint story, end to end

You are executing ONE planned story. Your kickoff prompt names the story doc, the sprint, your
EXECUTION MODE, and your `/goal`. This contract is the how. Product scope and decisions in the
story doc and `00-overview.md` are settled by default; the operator may amend them live at the
brainstorm gate, and every amendment is recorded in STORY-FEEDBACK.md. If you find a wrong
premise, an internal contradiction, or a genuine product ambiguity, follow "Divergences and
handback" below — never build around a broken premise.

## 0. Preflight

- `git fetch origin`
- If `sprint/{NN}-*` already exists on any ref, the story is taken. STOP and report; never co-opt
  someone else's branch.
- `git switch -c sprint/{NN}-{SLUG} origin/main` — NEVER run `git checkout main`: trunk is checked
  out in another worktree and the command fails. Trunk is `origin/main`; if the project uses
  another trunk, `00-overview.md` says so. (`sprint-status.sh` honors `SPRINT_TRUNK`; that
  asymmetry is known and not yours to fix.) Until your first story commit this branch is a
  **claim**: it carries no story commits and exists to signal DOING to other sessions.
- Confirm this worktree is linked to the real deploy project before any deploy (see AGENTS.md).

## 1. Investigate — read-only

- Do the story doc's "Start by verifying" first. Reproduce the bug / establish the baseline
  BEFORE changing anything, capturing the "before" screenshots while you are there. Restate
  In/Out of scope.

## 2. Brainstorm gate — `loop: full` only

Your kickoff prompt's planning-depth line says whether this phase applies; `loop: direct`
stories skip to step 3.

- Present the investigation findings to the operator: what you verified, what surprised you, and
  2-3 candidate approaches with trade-offs and your recommendation.
- Decisions in the story doc are settled by default; the operator may amend them here. Record
  every amendment in STORY-FEEDBACK.md — the append rides your story commits.
- If findings diverge from the story doc, apply "Divergences and handback" below before writing
  any code.
- This gate is interactive by design. The single-late-checkpoint rule (and the "progress pings"
  mistake below) applies only AFTER the operator says proceed.

## 3. Plan

- `loop: full`: write the spec and the plan as files on the story branch, reflecting what the
  brainstorm settled.
- `loop: direct`: the story is fully defined — write a short TDD plan and go.

## 4. Implement

- TDD: failing test first.
- Stay strictly inside `ownership.owns`; never touch `do_not_touch`.
- Every commit you make for this story carries the trailer block from your kickoff prompt:

      Story: {NN}
      Sprint: {SPRINT}

  This is the only record that the story landed. A commit without both is invisible to sprint
  status.

- Orchestration (ultracode / `ultra`) never waives this contract: every commit — including
  commits produced by subagents or workflow stages — carries both trailers, `ownership.owns` /
  `do_not_touch` bind all subagents, and there is a single writer per file at any moment.

## 5. Validate locally

Tests + typecheck; drive the story doc's Browser Verification locally; capture the "after"
screenshots; open any produced artifact. Fix until green.

## 6. Merge & deploy — AUTONOMOUS mode only

Under STOP AT PR: open a PR, do not merge, do not deploy. Trailers still go on every commit; `DONE`
flips when the human merges. Skip to step 8.

- Gate: story tests + typecheck + a production build all pass, and the story's commits carry BOTH
  trailers.
- Merge into trunk in `00-overview.md`'s merge order; ensure trunk is green.
- If the push is rejected because another session landed first: `git pull --rebase` and retry ONCE.
  Rejected again → STOP and report. Never force-push.
- Deploy with the project's deploy command (AGENTS.md).

## 7. Verify on prod — AUTONOMOUS mode only

- Drive the Browser Verification against the LIVE URL with a real test account; capture prod
  screenshots.
- Defect → fix, re-gate, redeploy, re-check. If prod breaks and it is not a fast fix → roll back
  (or revert the merge) and report. Never leave prod broken.

## 8. Hand off

- Append findings to STORY-FEEDBACK.md, including any surface you had to add to `surfaces:`.
- Produce the "How to test this yourself" section: what changed · live URL + role/account · exact
  steps, expected vs observed · test data/accounts · evidence (inline screenshots + provenance) ·
  risk + how to roll back · checks run (commands + results, build, deploy id) · open questions.
- Tracker: fire the `card.done` intent per the project's tracker binding. Where attachments are
  impossible (e.g. the Asana V2 MCP), the written hand-back reaches the card via `add_comment`.
- State branch, files, tests + results, deploy id.

## Divergences and handback

When investigation or brainstorm findings diverge from the story doc, grade the blast radius:

- **Contained** — the divergence stays inside this story's scope and ownership (the bug is in Y,
  not X; same shape of fix). Interactive session: settle it with the operator, record it in
  STORY-FEEDBACK.md, proceed. Non-interactive transport: proceed under a recorded amendment
  without stopping.
- **Cross-boundary** — the divergence invalidates the premise, reshapes other stories, changes
  merge order or waves, or reveals the story should not exist. Interactive session: present the
  premise, the contradicting evidence, and the blast radius, then ask the operator:
  **hand back to sprint-orchestrator now, or continue?** Non-interactive transport: hand back
  without asking — stopping is what the wrong-premise interrupt has always required.

On hand back:

1. Append a REPLAN event to STORY-FEEDBACK.md. Events are immutable, carry an id, and are never
   edited afterwards:

       ## REPLAN — rp-YYYYMMDD-<n> — Story {NN}
       - Premise as written: <quote from the story doc>
       - Contradicting evidence: <file/symbol/command anchors>
       - Blast radius: <affected stories, dependency edges, waves>
       - Recommendation: <one line>

2. Publish it: commit the append as a docs-only commit with NO `Story:`/`Sprint:` trailers — a
   trailered commit reaching trunk would flip this story to DONE — on a
   `sprint-docs/rp-YYYYMMDD-<n>` branch cut from `origin/main`, not on the claim branch.
   `execution: autonomous`: merge it to trunk now. `stop-at-pr`: open a docs-only PR.
3. Release the claim: remove your worktree if you created one, then delete the `sprint/{NN}-*`
   branch — it has no story commits. The story reads TODO again.
4. Stop. Tell the operator to re-invoke `/sprint-orchestrator` on the sprint directory; the next
   plan session resolves the event before planning anything else.

If the operator says continue, record the decision in STORY-FEEDBACK.md and proceed under the
amended understanding.

## Direction stories — `flow: direction`

The deliverable is an investigation dossier, not product code. Steps 0-2 apply unchanged — the
brainstorm gate is where the operator shapes the direction. Then:

- Write the dossier to the sprint directory as `dossier-{NN}.md` on the story branch. The name
  must not match `[0-9]*.md`: `sprint-status.sh` enumerates those as stories, and
  `{NN}-dossier.md` would surface as a phantom second story {NN}.
- Commit it with the story's normal trailer block. By convention the dossier commit is the ONLY
  trailered commit a direction story makes.
- Append a DIRECTION event to STORY-FEEDBACK.md (same id scheme, same immutability), in the same
  commit:

      ## DIRECTION — dr-YYYYMMDD-<n> — Story {NN}
      - Dossier: <path>
      - Recommendation: <one line>

- No TDD, no test/typecheck/build gates, no browser evidence: the merge gate is that the diff is
  docs-only. Merge or open a PR per your EXECUTION MODE; the tracker `card.done` intent still
  fires.
- Done means: dossier merged, DIRECTION event appended, and the operator has read the dossier —
  a dossier is an artifact, and human inspection of artifacts is part of done.
- Then stop. Re-entering planning is the operator's move, in a fresh strongest-model planner
  session — never this session, which sits in a story worktree on a stale branch.

## Evidence (frontend stories)

- `surfaces:` in the story doc is a floor, not a ceiling. When verification reveals a surface the
  planner missed: add it, capture it, record the addition in STORY-FEEDBACK.md.
- For each `(route, state)`: **before** and **after** locally, plus **after** on the live URL.
- A screenshot from an **approved driver** is mandatory; the project's AGENTS.md names the approved
  drivers. Banned unconditionally: a DOM class or attribute check standing in for a screenshot; any
  driver not listed in AGENTS.md; omitting which driver produced a shot.
- If no approved driver can drive the flow, HALT and report what you tried.
- Every shot declares its provenance:

  | Surface | State | Driver | Viewport | Role | Client |
  |---|---|---|---|---|---|

- Files land in `~/.sprint-evidence/{SPRINT}/{NN}-{SLUG}/`. Never `/tmp`, never inside a git
  worktree — the worktree dies long before review.
- The hand-back embeds the screenshots inline in the final message (Codex.app renders them),
  grouped before/after per surface. That is the human's confirmation step.
- `frontend: false` → no screenshots, but a produced artifact (PDF, email, export) must still be
  opened and confirmed by a human.

## Interrupts — the only three

Check back at your `/goal`. Surface earlier ONLY for:

1. a wrong premise or genuine product ambiguity — graded and handled per "Divergences and
   handback";
2. an inability to keep prod green (roll back and report);
3. no approved driver can drive the browser verification.

## Common mistakes

- Never run `git checkout main` — trunk lives in another worktree; use
  `git switch -c <branch> origin/main`.
- Commits without both trailers — the story ships and sprint status calls it TODO forever.
- A REPLAN or DIRECTION event committed WITH story trailers — flips the story's derived state.
- Naming a dossier `{NN}-dossier.md` — enumerates as a phantom story; the name is
  `dossier-{NN}.md`.
- Co-opting an existing `sprint/NN-*` branch instead of stopping.
- Force-pushing after a rejected push. Rebase once, retry once, then stop.
- Deploying from a feature branch instead of merging to trunk first — "live" then ≠ what you
  tested.
- Silently swapping browser drivers — legal only if AGENTS.md approves the driver and the hand-back
  declares it.
- Writing evidence to `/tmp` or into the worktree — both vanish before review.
- Progress pings mid-run — defeats the single-checkpoint purpose. The brainstorm gate (step 2)
  is the sanctioned exception, and it ends when the operator says proceed.
````

- [ ] **Step 5: Run lint to verify all pins pass**

Run: `test/lint-skills.sh`
Expected: `0 failed`. If `contract: first interrupt condition` fails, the phrase `wrong premise` was lost from the Interrupts section — restore it.

- [ ] **Step 6: Commit**

```bash
cd ~/claude-skills && git branch --show-current && git status --short && git add agent-handoff/EXECUTION.md test/lint-skills.sh && git commit -m "feat(agent-handoff): brainstorm gate, handback events, direction stories in contract"
```

---

### Task 2: sprint-orchestrator/SKILL.md — loop guide, event sweep, subagent execution, direction stories

**Files:**
- Modify: `sprint-orchestrator/SKILL.md`
- Modify: `test/lint-skills.sh` (add pins in the `--- sprint-orchestrator ---` section, after line 59)

**Interfaces:**
- Consumes: event headings and dossier naming exactly as Task 1 wrote them (`## REPLAN — rp-YYYYMMDD-<n> — Story NN`, `## DIRECTION — dr-YYYYMMDD-<n> — Story NN`, `dossier-NN.md`).
- Produces: `## RESOLUTION — <id>` heading; `flow` comment string `# mechanical | design-heavy | direction`; the section title `## Executing Direct Stories In-Session` that the README (Task 6) references.

- [ ] **Step 1: Add the failing lint pins**

In `test/lint-skills.sh`, insert after the `orchestrator: DONE row requires the Sprint trailer too` block (currently ends line 59), before `# --- agent-handoff (SKILL.md) ---`:

```bash
has   "orchestrator: loop is a judgment call"   "judgment call, not a tier rule" "$ORCH"
has   "orchestrator: brainstorm cue"            "design space is open"     "$ORCH"
has   "orchestrator: direct cue"                "well-trodden in-repo pattern" "$ORCH"
has   "orchestrator: REPLAN event heading"      "## REPLAN — rp-"          "$ORCH"
has   "orchestrator: DIRECTION event heading"   "## DIRECTION — dr-"       "$ORCH"
has   "orchestrator: RESOLUTION event heading"  "## RESOLUTION —"          "$ORCH"
has   "orchestrator: events are immutable"      "Never edit an existing event" "$ORCH"
has   "orchestrator: direction flow value"      "# mechanical | design-heavy | direction" "$ORCH"
has   "orchestrator: dossier naming"            "dossier-NN.md"            "$ORCH"
has   "orchestrator: subagents gated on recap"  "user approves the recap"  "$ORCH"
has   "orchestrator: publish before firing"     "Publish before firing"    "$ORCH"
has   "orchestrator: one planner per sprint dir" "One planner per sprint dir" "$ORCH"
```

- [ ] **Step 2: Run lint to verify exactly these 12 pins fail**

Run: `test/lint-skills.sh | grep FAIL`
Expected: the 12 new pins FAIL; everything else passes.

- [ ] **Step 3: Edit SKILL.md — six edits**

Edit A — the contract line (intro paragraph). Replace:

```markdown
Manual sprint-planning skill for turning raw inputs into independent story handoffs. It plans and hands off; it does not implement stories, merge branches, or declare work done.
```

with:

```markdown
Manual sprint-planning skill for turning raw inputs into independent story handoffs. It plans and hands off; the one sanctioned exception is firing `loop: direct` stories as subagents after the user approves the recap (see Executing Direct Stories In-Session). It never implements stories inline and never declares work done.
```

Edit B — the Plan Session `loop:` definitions. Replace:

```markdown
This is high-level planning backed by in-depth research — never per-story implementation planning.
`loop: full` (default): the story's execution session runs its own self-directed brainstorm → spec
→ plan → execute phases under its single late `/goal` checkpoint. `loop: direct`: the story is
simple enough to define fully here; the executor goes straight to a short TDD plan, and the story
may be delegated to a cheaper transport (subagent, `codex exec`, `claude -p`). Either way the
lifecycle contract is identical — `loop:` never waives trailers, branch discipline, or gates.
```

with:

```markdown
This is high-level planning backed by in-depth research — never per-story implementation planning.
`loop: full` (default): the story's execution session opens with read-only investigation and an
interactive brainstorm with the operator before any code — the story doc is the input to that
brainstorm, not a replacement for it. `loop: direct`: the story is simple enough to define fully
here; the executor goes straight to a short TDD plan, and the story may be delegated to a cheaper
transport (subagent, `codex exec`, `claude -p`). Either way the lifecycle contract is identical —
`loop:` never waives trailers, branch discipline, or gates.

`loop:` is a judgment call, not a tier rule — ask the user when unsure. Brainstorm (`full`) when
the design space is open (multiple valid approaches with genuinely different trade-offs), when
investigation could plausibly reshape the approach (novel integration, unfamiliar subsystem, a
premise this session could only verify shallowly), or when user-facing design judgment is
involved. Go `direct` when the work repeats a well-trodden in-repo pattern, is a mechanical
sweep, rename, or config change, is a bugfix whose root cause and fix shape this session already
found, or when this session already verified everything the executor would otherwise
investigate. As a tendency, not a rule: S/A stories almost always read `full`, B usually does,
C usually reads `direct`.
```

Edit C — add step 7 to the numbered Plan Session list, after step 6 (`Recap open stories…`):

```markdown
7. If the user approves at the recap, execute chosen `loop: direct` stories as subagents (see
   Executing Direct Stories In-Session); otherwise every story goes out as a rendered handoff.
```

Edit D — the wave-checkpoint paragraph. Replace:

```markdown
At each wave boundary (the wave's stories read `DONE` in `sprint-status.sh`), the user re-invokes
this skill on the sprint directory. The planner then reads `sprint-status.sh` output and
`STORY-FEEDBACK.md`, gives its opinion on sprint progress — what landed, what drifted, what
feedback changes the remaining plan — re-verifies each stub against the now-current code, and
writes the next wave's story docs, cutting or reframing stubs whose premise no longer holds.
```

with:

```markdown
At each wave boundary (the wave's stories read `DONE` in `sprint-status.sh`), the user re-invokes
this skill on the sprint directory. On ANY re-invocation of an existing sprint dir — wave
boundary, handback, or a landed direction story — FIRST sweep `STORY-FEEDBACK.md` for unresolved
feedback events: every `## REPLAN — rp-YYYYMMDD-<n> — Story NN` or
`## DIRECTION — dr-YYYYMMDD-<n> — Story NN` block with no matching `## RESOLUTION — <id>` block.
Re-verify each against current source truth; rewrite, cut, or split the affected story docs (for
a DIRECTION dossier: plan the follow-on stories or record why not); then append the resolution as
its own immutable event — `## RESOLUTION — <id>` with a `- Resolution:` line. Never edit an
existing event block. Only then read `sprint-status.sh` output and the rest of
`STORY-FEEDBACK.md`, give an opinion on sprint progress — what landed, what drifted, what
feedback changes the remaining plan — re-verify each stub against the now-current code, and
write the next wave's story docs, cutting or reframing stubs whose premise no longer holds.

One planner per sprint dir at a time: concurrent plan sessions collide on story numbers and
merge order. After a direction story lands, re-enter planning in a fresh strongest-model
session, never in the executor's thread.
```

Edit E — Story Doc Shape. In the frontmatter template, replace the line:

```markdown
flow: mechanical             # mechanical | design-heavy
```

with:

```markdown
flow: mechanical             # mechanical | design-heavy | direction
```

and add this paragraph after the `frontend:` explanation paragraph (the one ending `When unsure, set it true and name the surface.`):

```markdown
`flow: direction` marks a story whose deliverable is an investigation dossier — planning input,
not product code. Direction stories are always `loop: full` and typically tier S. The executor
writes `dossier-NN.md` into the sprint directory (never `NN-dossier.md`: `sprint-status.sh`
enumerates `[0-9]*.md` files as stories, so that name surfaces a phantom story) and the dossier
commit is the story's only trailered commit. EXECUTION.md carries the full alternate terminal
path; the kickoff renders `Use skills: none` for direction stories.
```

Edit F — Guardrails. Replace the first guardrail bullet:

```markdown
- If verification contradicts a story premise, stop and report the contradiction before building around it.
```

with:

```markdown
- If verification contradicts a story premise, follow EXECUTION.md's divergence protocol: contained divergences proceed under a recorded amendment; cross-boundary ones offer the operator the handback that writes a REPLAN event. Never build around a broken premise.
```

Then add this new section between `## Waves Are Planned Incrementally` and `## Integration Is Planned Here, Performed Elsewhere`:

```markdown
## Executing Direct Stories In-Session

This skill's only sanctioned in-session execution. It never starts before the user approves the
recap — the gate exists so a bad plan is seen before it runs.

- **Publish before firing.** Commit and push the sprint planning docs (story docs,
  `00-overview.md`, `STORY-FEEDBACK.md`) to trunk first: a fresh worktree reads planning docs
  via `git show origin/main:<path>` and cannot see this session's uncommitted files. Pasted
  cross-session kickoffs have the same dependency.
- Each subagent runs ONE `loop: direct` story end-to-end in an isolated worktree from its
  rendered kickoff prompt, bound by EXECUTION.md unchanged: trailers on every commit,
  `ownership.owns` / `do_not_touch`, single writer per file. `sprint-status.sh` cannot tell the
  transports apart — state stays git-derived.
- Scheduling is the plan itself: fire only stories whose `depends_on` are DONE and whose
  ownership is disjoint from every in-flight story; shared-hotspot stories run serially in
  `00-overview.md`'s merge order.
- First failure stops the fleet: report what ran and what failed, leave the failed branch for
  inspection, no automatic retries.
- Transport is resolved at handoff time, never at plan time: when Claude capacity is tight, the
  same stories render as `codex exec` prints instead. Never subagent a `loop: full` story (they
  need an interactive session); `frontend: true` stories are a poor fit — their evidence path
  ends in Codex.app visual validation.
```

- [ ] **Step 4: Run lint to verify all pins pass**

Run: `test/lint-skills.sh`
Expected: `0 failed`. Watch specifically: `orchestrator: no unconditional 'do not merge'` (the new prose must not contain the phrase `do not merge`) and `orchestrator: no narrow story glob` (the dossier paragraph says `[0-9]*.md`, which is fine — the banned string is `[0-9][0-9]-*.md`).

- [ ] **Step 5: Commit**

```bash
cd ~/claude-skills && git branch --show-current && git status --short && git add sprint-orchestrator/SKILL.md test/lint-skills.sh && git commit -m "feat(sprint-orchestrator): loop guide, event sweep, in-session direct execution"
```

---

### Task 3: agent-handoff/SKILL.md — kickoff template changes

**Files:**
- Modify: `agent-handoff/SKILL.md` (story-execution mode section)
- Modify: `test/lint-skills.sh` (add pins in the `--- agent-handoff (SKILL.md) ---` section, after line 98)

**Interfaces:**
- Consumes: the two depth-line strings from the Global Constraints (must match Task 1's EXECUTION.md wording and Task 4's renderer byte-for-byte).
- Produces: the template lines `wave-handoffs.sh` mirrors in Task 4 — the SETTLED replacement, the planning-depth line, the handback hard rule, the direction skills mapping.

- [ ] **Step 1: Add the failing lint pins**

In `test/lint-skills.sh`, insert after the `ladder: orchestrator and handoff tables in sync` block (currently ends line 98), before `# --- agent-handoff (EXECUTION.md...) ---`:

```bash
has   "handoff: interactive depth line"      "investigation + interactive brainstorm phase with the operator first" "$AH"
hasnt "handoff: no self-directed wording"    "self-directed brainstorm" "$AH"
has   "handoff: settled by default"          "settled by default" "$AH"
hasnt "handoff: no hard SETTLED wording"     "are SETTLED"        "$AH"
has   "handoff: handback hard rule"          "publish the REPLAN event" "$AH"
has   "handoff: direction renders no skills" "\`flow: direction\` → none" "$AH"
```

- [ ] **Step 2: Run lint to verify exactly these 6 pins fail**

Run: `test/lint-skills.sh | grep FAIL`
Expected: the 6 new pins FAIL (the two `hasnt` pins fail because both strings exist today); everything else passes.

- [ ] **Step 3: Edit the story-execution mode section**

Edit A — the `loop:` bullet. Replace:

```markdown
- `loop:` sets the planning-depth sentence: `full` → run the contract's self-directed
  brainstorm → spec → plan phase first; `direct` → the story is fully defined, go straight to a
  short TDD plan. `loop: direct` also allows a `codex-cli` / `claude-cli` / subagent target;
  `loop: full` stories belong in an interactive session (`codex-app` or `claude-session`).
```

with:

```markdown
- `loop:` sets the planning-depth sentence: `full` → run the contract's investigation +
  interactive brainstorm phase with the operator first; `direct` → the story is fully defined —
  go straight to a short TDD plan. `loop: direct` also allows a `codex-cli` / `claude-cli` /
  subagent target; `loop: full` stories belong in an interactive session (`codex-app` or
  `claude-session`).
- The `Use skills:` line comes from the story's `flow:` — `mechanical` →
  superpowers:test-driven-development; `design-heavy` → superpowers:brainstorming +
  superpowers:test-driven-development; `flow: direction` → none: the brainstorm is the
  contract's own gate and the deliverable is a dossier, so no implementation skill applies.
```

Edit B — the fenced kickoff template. Replace the template's middle lines:

```
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
```

with:

```
(AGENTS.md / CLAUDE.md). If any are absent from this worktree, read them from trunk with
`git show origin/main:<path>` — never copy them in. Product scope and decisions there are
settled by default; the operator may amend them at the brainstorm gate, and divergences follow
the contract's handback protocol.
Execution contract: {~/.codex|~/.claude}/skills/agent-handoff/EXECUTION.md — follow it exactly.
Planning depth: {run the contract's investigation + interactive brainstorm phase with the operator
first | the story is fully defined — go straight to a short TDD plan}.
Use skills: {from the story's flow — e.g. superpowers:test-driven-development; `flow: direction` → none}
Hard rules: every commit carries `Story: {NN}` and `Sprint: {SPRINT}` (verbatim);
never `git checkout main`; if sprint/{NN}-* already exists on any ref the story is taken — stop;
on handback publish the REPLAN event (docs-only, no trailers) and release the claim branch;
never leave prod broken.
```

- [ ] **Step 4: Run lint to verify all pins pass**

Run: `test/lint-skills.sh`
Expected: `0 failed`. Watch: `handoff: git checkout main only ever negated` must still pass (the template line keeps the negation `never \`git checkout main\``).

- [ ] **Step 5: Commit**

```bash
cd ~/claude-skills && git branch --show-current && git status --short && git add agent-handoff/SKILL.md test/lint-skills.sh && git commit -m "feat(agent-handoff): interactive depth line, handback rule, direction mapping"
```

---

### Task 4: wave-handoffs.sh — depth strings, direction mapping, unresolved-event warning (TDD)

**Files:**
- Modify: `sprint-orchestrator/test/test-wave-handoffs.sh`
- Modify: `sprint-orchestrator/wave-handoffs.sh`
- Modify: `test/lint-skills.sh` (renderer-sync pins at the end, before the summary `printf`)

**Interfaces:**
- Consumes: the exact template strings Task 3 put in `agent-handoff/SKILL.md`; the event heading shapes from Task 1.
- Produces: stderr warning prefix `wave-handoffs: WARNING: unresolved feedback events`; stdout recap line starting `> **Unresolved feedback events**`.

- [ ] **Step 1: Extend the fixture writer so extras can override defaults**

In `test-wave-handoffs.sh`, replace the `story()` function:

```bash
story() {  # $1=NN $2=slug, remaining args = extra frontmatter lines
  local nn="$1" slug="$2"; shift 2
  { printf -- '---\nstory: %s\ntitle: %s\nconversation: "Story %s: Fixture Case Doc"\n' "$nn" "$slug" "$nn"
    printf 'sprint: 2026-07-10-fixture-sprint\nexecution: stop-at-pr\nflow: mechanical\nloop: direct\nwave: 1\n'
    local line; for line in "$@"; do printf '%s\n' "$line"; done
    printf -- '---\n\n## Objective\nFixture objective %s.\n\n## Goal\n\n/goal fixture goal %s\n' "$nn" "$nn"
  } > "$SPRINT/$nn-$slug.md"
}
```

with (extras printed BEFORE the defaults, so `fm_get`'s `grep -m1` lets an extra `loop:`/`flow:` line win):

```bash
story() {  # $1=NN $2=slug, remaining args = extra frontmatter lines (win over defaults via grep -m1)
  local nn="$1" slug="$2"; shift 2
  { printf -- '---\nstory: %s\ntitle: %s\nconversation: "Story %s: Fixture Case Doc"\n' "$nn" "$slug" "$nn"
    local line; for line in "$@"; do printf '%s\n' "$line"; done
    printf 'sprint: 2026-07-10-fixture-sprint\nexecution: stop-at-pr\nflow: mechanical\nloop: direct\nwave: 1\n'
    printf -- '---\n\n## Objective\nFixture objective %s.\n\n## Goal\n\n/goal fixture goal %s\n' "$nn" "$nn"
  } > "$SPRINT/$nn-$slug.md"
}
```

- [ ] **Step 2: Add the failing fixtures and assertions**

After the `story 19 bare-legacy` line, add:

```bash
story 20 full-loop       'driver_hint: claude' 'tier: B' 'tier_why: fixture' 'loop: full'
story 21 direction-probe 'driver_hint: claude' 'tier: S' 'tier_why: fixture' 'loop: full' 'flow: direction'
```

After the existing `no Launch text inside fenced prompts` check (line 55), add:

```bash
has "full loop renders interactive depth"  "$OUTPUT" 'run the contract'"'"'s investigation + interactive brainstorm phase with the operator first'
has "direct loop keeps direct depth"       "$OUTPUT" 'the story is fully defined — go straight to a short TDD plan'
has "direction renders no skills"          "$OUTPUT" 'Use skills: none'
has "settled-by-default wording rendered"  "$OUTPUT" 'settled by default'
has "handback hard rule rendered"          "$OUTPUT" 'publish the REPLAN event (docs-only, no trailers) and release the claim branch'
case "$OUTPUT" in *"are SETTLED"*) no "old SETTLED wording gone";; *) ok "old SETTLED wording gone";; esac

# ---- Unresolved feedback events: warn on stderr, recap line on stdout ----
cat > "$SPRINT/STORY-FEEDBACK.md" <<'EOF'
# Story feedback

## REPLAN — rp-20260701-01 — Story 07
- Premise as written: fixture premise
- Contradicting evidence: fixture
- Blast radius: fixture
- Recommendation: fixture

## RESOLUTION — rp-20260701-01
- Resolution: fixture resolved

## REPLAN — rp-20260702-01 — Story 07
- Premise as written: fixture second premise
- Contradicting evidence: fixture
- Blast radius: fixture
- Recommendation: fixture

## DIRECTION — dr-20260702-02 — Story 09
- Dossier: docs/sprints/fixture/dossier-09.md
- Recommendation: fixture
EOF

WERR="$(mktemp)"
WOUT="$("$WH" "$SPRINT" 1 2>"$WERR")"
WERRTXT="$(cat "$WERR")"
has "warning names unresolved replan id"    "$WERRTXT" 'rp-20260702-01 (Story 07)'
has "warning names unresolved direction id" "$WERRTXT" 'dr-20260702-02 (Story 09)'
case "$WERRTXT" in *rp-20260701-01*) no "resolved id not warned";; *) ok "resolved id not warned";; esac
has "recap carries the unresolved line"     "$WOUT"    '> **Unresolved feedback events**'
case "$WOUT" in *"wave-handoffs: WARNING"*) no "stderr warning stays off stdout";; *) ok "stderr warning stays off stdout";; esac

cat >> "$SPRINT/STORY-FEEDBACK.md" <<'EOF'

## RESOLUTION — rp-20260702-01
- Resolution: fixture

## RESOLUTION — dr-20260702-02
- Resolution: fixture
EOF
RERR="$(mktemp)"
"$WH" "$SPRINT" 1 >/dev/null 2>"$RERR"
[ -s "$RERR" ] && no "no warning when all events resolved (got: '$(cat "$RERR")')" || ok "no warning when all events resolved"
```

Note: the feedback fixture is created AFTER the primary `OUTPUT` capture (line 36), so the original run stays warning-free.

- [ ] **Step 3: Run the test to verify the new assertions fail**

Run: `sprint-orchestrator/test/test-wave-handoffs.sh | grep FAIL`
Expected: 8 assertions FAIL — `full loop renders interactive depth`, `direction renders no skills`, `settled-by-default wording rendered`, `handback hard rule rendered`, `old SETTLED wording gone`, the two `warning names…` ids, and `recap carries the unresolved line`. All 17 pre-existing assertions still pass, and so does `direct loop keeps direct depth` (that string is unchanged from today). `resolved id not warned`, `stderr warning stays off stdout`, and `no warning when all events resolved` vacuously pass until the warning exists — acceptable.

- [ ] **Step 4: Implement in wave-handoffs.sh**

Edit A — the `depth` case (currently lines 137-141). Replace:

```bash
  case "$loop" in
    full)   depth="run the contract's self-directed brainstorm → spec → plan phase first" ;;
    direct) depth="the story is fully defined — go straight to a short TDD plan" ;;
    *)      depth="$loop" ;;
  esac
```

with:

```bash
  case "$loop" in
    full)   depth="run the contract's investigation + interactive brainstorm phase with the operator first" ;;
    direct) depth="the story is fully defined — go straight to a short TDD plan" ;;
    *)      depth="$loop" ;;
  esac
```

Edit B — the skills mapping (currently lines 146-147). Replace:

```bash
  skills="superpowers:test-driven-development"
  [ "$flow" = "design-heavy" ] && skills="superpowers:brainstorming, superpowers:test-driven-development"
```

with:

```bash
  skills="superpowers:test-driven-development"
  [ "$flow" = "design-heavy" ] && skills="superpowers:brainstorming, superpowers:test-driven-development"
  [ "$flow" = "direction" ] && skills="none"
```

Edit C — the SETTLED lines in the kickoff printf block (currently lines 157-158). Replace:

```bash
  printf '`git show origin/main:<path>` — never copy them in. Product scope and decisions there are SETTLED;\n'
  printf 'stop and ask for a wrong premise or genuine product ambiguity (the contract'"'"'s other interrupts still apply).\n'
```

with:

```bash
  printf '`git show origin/main:<path>` — never copy them in. Product scope and decisions there are\n'
  printf 'settled by default; the operator may amend them at the brainstorm gate, and divergences follow\n'
  printf 'the contract'"'"'s handback protocol.\n'
```

("settled by default" must stay contiguous on one line — the lint pins are line-based `grep -qF`.)

Edit D — the Hard rules block (currently lines 162-164). Replace:

```bash
  printf 'Hard rules: every commit carries `Story: %s` and `Sprint: %s` (verbatim);\n' "$story" "${sprint_fm:-$sprint_name}"
  printf 'never `git checkout main`; if sprint/%s-* already exists on any ref the story is taken — stop;\n' "$story"
  printf 'never leave prod broken.\n\n'
```

with:

```bash
  printf 'Hard rules: every commit carries `Story: %s` and `Sprint: %s` (verbatim);\n' "$story" "${sprint_fm:-$sprint_name}"
  printf 'never `git checkout main`; if sprint/%s-* already exists on any ref the story is taken — stop;\n' "$story"
  printf 'on handback publish the REPLAN event (docs-only, no trailers) and release the claim branch;\n'
  printf 'never leave prod broken.\n\n'
```

Edit E — the warning. Insert after the docs-collection guard (currently line 97, `|| { echo "wave-handoffs: no story docs..." ...; exit 2; }`), before `# ---- Header + recap ----`:

```bash
# ---- Unresolved feedback events: warn, never block (operator's explicit choice) ----
feedback="$sprint_dir/STORY-FEEDBACK.md"
unresolved=""
if [ -f "$feedback" ]; then
  unresolved="$(awk '
    /^## (REPLAN|DIRECTION) — /{ids[$4]=$7}
    /^## RESOLUTION — /{resolved[$4]=1}
    END{for (id in ids) if (!(id in resolved)) printf "%s (Story %s), ", id, ids[id]}' "$feedback")"
  unresolved="${unresolved%, }"
fi
[ -n "$unresolved" ] \
  && printf 'wave-handoffs: WARNING: unresolved feedback events — resolve via /sprint-orchestrator before kickoff: %s\n' "$unresolved" >&2
```

(Field positions: in `## REPLAN — rp-20260702-01 — Story 07`, awk's `$4` is the id and `$7` the story number; in `## RESOLUTION — rp-20260702-01`, `$4` is the id.)

Edit F — the recap line. Insert after the at-a-glance loop's closing `done` (currently line 116), before the `printf '\nThese run in parallel; …'` line:

```bash
[ -n "$unresolved" ] \
  && printf '\n> **Unresolved feedback events** — resolve via `/sprint-orchestrator` before kickoff: %s\n' "$unresolved"
```

- [ ] **Step 5: Run the wave test to verify everything passes**

Run: `sprint-orchestrator/test/test-wave-handoffs.sh`
Expected: `0 failed` (17 pre-existing + 11 new assertions).

- [ ] **Step 6: Add the renderer-sync lint pins**

In `test/lint-skills.sh`, add before the final summary `printf` (currently line 147):

```bash
# --- wave-handoffs.sh (renderer must mirror agent-handoff/SKILL.md's template) ---
WHS="$HERE/../sprint-orchestrator/wave-handoffs.sh"
has   "renderer: interactive depth string"   "investigation + interactive brainstorm phase with the operator first" "$WHS"
has   "renderer: direction renders no skills" 'skills="none"'     "$WHS"
has   "renderer: handback hard rule"         "publish the REPLAN event" "$WHS"
has   "renderer: unresolved-event warning"   "unresolved feedback events" "$WHS"
hasnt "renderer: no hard SETTLED wording"    "are SETTLED"        "$WHS"
hasnt "renderer: no self-directed wording"   "self-directed brainstorm" "$WHS"
```

- [ ] **Step 7: Run lint, verify all pass**

Run: `test/lint-skills.sh`
Expected: `0 failed`.

- [ ] **Step 8: Commit**

```bash
cd ~/claude-skills && git branch --show-current && git status --short && git add sprint-orchestrator/wave-handoffs.sh sprint-orchestrator/test/test-wave-handoffs.sh test/lint-skills.sh && git commit -m "feat(sprint-orchestrator): render new depth lines and unresolved-event warning"
```

---

### Task 5: sprint-status.sh dossier-enumeration fixture

**Files:**
- Modify: `sprint-orchestrator/test/test-sprint-status.sh` (no change to `sprint-status.sh` itself)

**Interfaces:**
- Consumes: the `dossier-NN.md` convention from Tasks 1-2.
- Produces: nothing consumed later; this pins the invariant the convention depends on.

- [ ] **Step 1: Add the failing-to-exist fixture**

In `test-sprint-status.sh`, insert before the `git worktree remove` cleanup line (currently line 168):

```bash
# --- Direction dossiers must not enumerate as stories ---
# dossier-NN.md is the convention BECAUSE it does not match the [0-9]*.md story
# glob. Story 09's row is the canary proving the hazard: NN-dossier.md DOES
# enumerate — if enumeration ever changes, these assertions flag it.
DD="docs/sprints/dossier-fixture"; mkdir -p "$DD"
echo "# 08-real" > "$DD/08-real.md"
echo "# dossier for 08" > "$DD/dossier-08.md"
echo "# phantom probe" > "$DD/09-dossier.md"
git add docs/sprints/dossier-fixture && git commit -q -m "chore: seed dossier fixture"
OUT_DD="$(SPRINT_TRUNK=main "$SUT" "$DD" 2>&1)"
state_is "$OUT_DD" 08 TODO
case "$OUT_DD" in *dossier-08*) no "dossier-08.md not enumerated";; *) ok "dossier-08.md not enumerated";; esac
state_is "$OUT_DD" 09 TODO
```

- [ ] **Step 2: Run the test**

Run: `sprint-orchestrator/test/test-sprint-status.sh`
Expected: `0 failed` (18 pre-existing + 3 new). These assertions pass against the unchanged script — they pin current behavior so the dossier convention can rely on it. If `dossier-08.md not enumerated` fails, the enumeration glob has changed and the dossier convention is broken — stop and reassess.

- [ ] **Step 3: Commit**

```bash
cd ~/claude-skills && git branch --show-current && git status --short && git add sprint-orchestrator/test/test-sprint-status.sh && git commit -m "test(sprint-orchestrator): pin dossier filenames outside story enumeration"
```

---

### Task 6: READMEs, full suite, merge

**Files:**
- Modify: `sprint-orchestrator/README.md`
- Modify: `agent-handoff/README.md`

**Interfaces:**
- Consumes: section title `Executing Direct Stories In-Session` (Task 2), event/dossier conventions (Tasks 1-2), warning behavior (Task 4).

- [ ] **Step 1: Update sprint-orchestrator/README.md**

Insert after the paragraph ending `…and it reassesses progress before writing the next wave.` (currently line 47):

```markdown
`loop: full` stories open with read-only investigation and an interactive brainstorm with you
before any code; `loop: direct` stories go straight to a short TDD plan. When execution findings
cross a story's boundary, the executor offers a handback: a `## REPLAN — rp-YYYYMMDD-<n> — Story NN`
event appended to `STORY-FEEDBACK.md`. Direction stories (`flow: direction`) deliver an
investigation dossier (`dossier-NN.md` — the name deliberately misses the `[0-9]*.md` story glob)
plus a `## DIRECTION — …` event. Any re-invocation of the skill on the sprint dir resolves
unresolved events first, appending `## RESOLUTION — <id>` blocks — events are immutable and
append-only. After you approve the recap, the planner may also execute `loop: direct` stories
itself as worktree-isolated subagents under the same execution contract (see Executing Direct
Stories In-Session in SKILL.md); when Claude capacity is tight the same stories render as Codex
handoffs instead.
```

In the `## Render a wave's handoffs` section, append to the paragraph ending `Exit code 2 on a bad sprint directory or a wave with no stories.`:

```markdown
If `STORY-FEEDBACK.md` carries unresolved REPLAN/DIRECTION events, the script warns on stderr and
puts a matching line in the rendered recap — it renders anyway; resolving is your call.
```

- [ ] **Step 2: Update agent-handoff/README.md**

Replace the story-execution row of the modes table:

```markdown
| `story-execution` | one planned sprint story, end to end | the story's late `/goal` checkpoint |
```

with:

```markdown
| `story-execution` | one planned sprint story, end to end | the story's late `/goal` checkpoint (after an operator brainstorm gate, for `loop: full`) |
```

And append to the paragraph ending `The prompt itself keeps only the catastrophic rules inline, with literal values.`:

```markdown
For `loop: full` stories the contract opens with read-only investigation and an interactive
brainstorm with the operator; divergences that cross the story boundary hand back to the sprint
planner via a REPLAN event in `STORY-FEEDBACK.md`.
```

- [ ] **Step 3: Run the full suite**

```bash
cd ~/claude-skills && test/lint-skills.sh && sprint-orchestrator/test/test-sprint-status.sh && sprint-orchestrator/test/test-wave-handoffs.sh && codex/test/test.sh
```

Expected: every script ends `… 0 failed` (codex/test/test.sh is untouched by this work and must stay green).

- [ ] **Step 4: Commit and merge**

```bash
cd ~/claude-skills && git branch --show-current && git status --short && git add sprint-orchestrator/README.md agent-handoff/README.md && git commit -m "docs: describe interactive loop, events, and in-session execution"
git switch main && git merge --no-ff feat/interactive-story-loop -m "feat: interactive story loop, feedback events, direction stories" && git branch -d feat/interactive-story-loop && git log --oneline -3
```

(Edits are live deploys once on `main` — the symlinked skills pick them up next session.)
