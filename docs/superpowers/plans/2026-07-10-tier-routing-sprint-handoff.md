# Tier Routing — Sprint/Handoff Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Sprint planning grades every story with a model tier + effort, and both renderers (agent-handoff prose skill, wave-handoffs.sh script) surface a concrete Launch recommendation to the operator at paste time.

**Architecture:** A four-row ladder table (tier → model per harness + depth default) is duplicated verbatim in `sprint-orchestrator/SKILL.md` and `agent-handoff/SKILL.md` and kept in sync by lint; `wave-handoffs.sh` encodes the same ladder as a bash case and is pinned by a new fixture test. Effort is written in story frontmatter only when deviating from the row default. Orchestration is a boolean flag that implies xhigh depth.

**Tech Stack:** Markdown skill prose, bash + grep/awk scripts and tests. No other runtime.

**Spec:** `docs/superpowers/specs/2026-07-10-model-tier-routing-design.md`

## Global Constraints

- Repo: `~/claude-skills`. All commands run from the repo root.
- Installed skills are symlinks into this repo — every commit is a live deploy to both harnesses.
- Tests are bash + grep only; no YAML parser, no other runtime.
- When pinned prose changes, the lint changes in the same commit.
- Never write `git checkout main` un-negated in any skill file (lint enforces).
- Conventional commits: `type(scope): description`, imperative, ≤72 chars.
- Stage explicit paths; never `git add -A`. Print `git branch --show-current` and `git status --short` alongside every commit.
- The ladder, verbatim (single source for this plan — copy exactly, including spacing):

```
| Tier | Claude (`--model`) | Codex (`-m`) | Depth default |
|------|--------------------|--------------|---------------|
| S | `fable` | — | high (xhigh only when capability-limited) |
| A | — | `gpt-5.6-sol` | xhigh |
| B | `opus` | `gpt-5.6-terra` | xhigh |
| C | `sonnet` | `gpt-5.6-luna` | high |
```

---

### Task 1: Ladder, grading, and frontmatter in sprint-orchestrator/SKILL.md

**Files:**
- Modify: `sprint-orchestrator/SKILL.md`
- Modify: `test/lint-skills.sh`

**Interfaces:**
- Produces: the canonical ladder table (four `| S/A/B/C |` rows) that Task 2 must duplicate byte-for-byte; frontmatter fields `tier:`, `tier_why:`, `effort:`+`effort_why:` (deviation only), `orchestrate:` that Tasks 2 and 4 consume.

- [ ] **Step 1: Add the failing lint checks**

In `test/lint-skills.sh`, after the existing line `has   "orchestrator: driver_why field"     "driver_why:"       "$ORCH"`, insert:

```bash
has   "orchestrator: tier field"            "tier:"              "$ORCH"
has   "orchestrator: tier_why field"        "tier_why:"          "$ORCH"
has   "orchestrator: effort_why field"      "effort_why:"        "$ORCH"
has   "orchestrator: orchestrate field"     "orchestrate:"       "$ORCH"
has   "orchestrator: orchestrate implies xhigh" "implies xhigh"  "$ORCH"
has   "orchestrator: effort only on deviation" "only when the story deviates" "$ORCH"
has   "orchestrator: tier from nature only" "tier:\` derives from the work's nature" "$ORCH"
orch_rows="$(grep -E '^\| [SABC] \|' "$ORCH")"
[ "$(printf '%s\n' "$orch_rows" | grep -c .)" = 4 ] \
  && ok "orchestrator: ladder has exactly 4 tier rows" \
  || no "orchestrator: ladder has exactly 4 tier rows (got: $(printf '%s\n' "$orch_rows" | grep -c .))"
```

- [ ] **Step 2: Run lint to verify the new checks fail**

Run: `test/lint-skills.sh | grep -E 'FAIL|passed'`
Expected: the 8 new checks FAIL (tier field, tier_why, effort_why, orchestrate, implies xhigh, only-on-deviation, tier-from-nature, 4 tier rows); previously passing checks still pass.

- [ ] **Step 3: Rewrite the strongest-model gate**

In `sprint-orchestrator/SKILL.md`, replace:

```markdown
Sprint planning gets the most capable model available. First, name the model you are running as.
If it is not the strongest tier reachable right now (today: Fable, else Opus, on Claude Code; Sol
at ultra effort on Codex), say so and offer to stop so the user can relaunch. No hard block — but
proceeding on a lesser model needs the user's explicit go-ahead, recorded in `00-overview.md`.
```

with:

```markdown
Sprint planning is coverage-shaped — every candidate is verified against source truth — so it
gets the most capable model available, in its orchestration mode. First, name the model you are
running as. If it is not the strongest tier reachable right now (today: Fable with ultracode,
else Opus with ultracode, on Claude Code; Sol at `ultra` effort on Codex), say so and offer to
stop so the user can relaunch. No hard block — but proceeding on a lesser model needs the user's
explicit go-ahead, recorded in `00-overview.md`.
```

- [ ] **Step 4: Add the ladder + grading section**

In `sprint-orchestrator/SKILL.md`, the Drivers section ends with:

```markdown
`driver_hint:` derives from the work's nature ONLY — never from today's capacity. The driver is
resolved at handoff time: required capability → the user's explicit say → current availability →
affinity.
```

Immediately after that paragraph, insert:

```markdown
## The Ladder

`tier:` grades the work's difficulty; `driver_hint:` grades its nature. Tier picks the row,
driver the column. S and A have one cell each, so they bind the harness at plan time; B and C
stay late-bound. Tiers are the operator's routing policy, not an empirical ordering.

| Tier | Claude (`--model`) | Codex (`-m`) | Depth default |
|------|--------------------|--------------|---------------|
| S | `fable` | — | high (xhigh only when capability-limited) |
| A | — | `gpt-5.6-sol` | xhigh |
| B | `opus` | `gpt-5.6-terra` | xhigh |
| C | `sonnet` | `gpt-5.6-luna` | high |

Depth scale, literal on both harnesses: `low | medium | high | xhigh | max`. Depth defaults are
operator policy for today's model generation — effort levels do not port across models; revisit
the defaults when a generation changes.

Orchestration shares the launch control with depth and implies xhigh: ultracode on Claude,
`model_reasoning_effort=ultra` on Codex. Sol and Terra support `ultra`; Luna does not — an
orchestrated C-tier codex story bumps to Terra.

Grading:

- **S** — ambiguous, architectural, novel design; a wrong turn is very expensive.
- **A** — hard but well-scoped cross-cutting work, mechanistic-leaning.
- **B** — multi-file but well-trodden.
- **C** — contained mechanical work; most `loop: direct` stories.

Like `driver_hint:`, `tier:` derives from the work's nature ONLY — never from today's capacity.
For S and A, `driver_hint` must equal the tier's harness (S → `claude`, A → `codex`); `either`
is invalid there, and a contradictory pair (`tier: S` + `driver_hint: codex`) is a planning
error.
```

- [ ] **Step 5: Add the frontmatter fields and deviation rules**

In the story-doc-shape template, replace:

```markdown
driver_hint: codex           # codex | claude | either — affinity from work nature only; resolved at handoff time
driver_why: <one line tying the hint to the work's nature>
branch: sprint/07-<slug>
```

with:

```markdown
driver_hint: codex           # codex | claude | either — affinity from work nature only; resolved at handoff time
driver_why: <one line tying the hint to the work's nature>
tier: B                      # opus (claude) / gpt-5.6-terra (codex) — the letter governs; the comment is advisory
tier_why: <one line grading the difficulty>
branch: sprint/07-<slug>
```

Then, after the template's closing code fence and before the paragraph starting `` `conversation:` is ``, insert (note the inner ```yaml fence — the whole block below, between the ````markdown markers, goes into the skill file):

````markdown
`effort:` is written only when the story deviates from its tier's depth default, and then an
`effort_why:` line is required — an absent `effort:` means "the current row default, resolved at
render time", so defaults never go stale inside story docs:

```yaml
effort: medium
effort_why: pure mechanical sweep, low ambiguity
```

`orchestrate: true` is written only when true: the story itself is coverage-shaped and
fire-and-verify — an audit, a migration, a repo-wide sweep where missing something costs more
than compute. It implies xhigh depth; never combine it with `effort:`. Interactive or
redirectable work never gets it (orchestrated workflows cannot pause for input).
````

- [ ] **Step 6: Run lint to verify it passes**

Run: `test/lint-skills.sh | grep -E 'FAIL|passed'`
Expected: `0 failed` — all new checks pass, no regressions. (The ladder-sync cross-file check does not exist yet; it arrives in Task 2.)

- [ ] **Step 7: Commit**

```bash
git branch --show-current && git status --short
git add sprint-orchestrator/SKILL.md test/lint-skills.sh
git commit -m "feat(sprint-orchestrator): grade stories with tier ladder and effort"
```

---

### Task 2: Ladder + Launch line in agent-handoff/SKILL.md

**Files:**
- Modify: `agent-handoff/SKILL.md`
- Modify: `test/lint-skills.sh`

**Interfaces:**
- Consumes: the ladder table from Task 1 (copy the four `| S/A/B/C |` rows byte-for-byte).
- Produces: the Launch-line format `Launch: <model> · <effort> (tier <T> …)` that Task 4's script mirrors; the rule that Launch lines live outside fenced blocks.

- [ ] **Step 1: Add the failing lint checks**

In `test/lint-skills.sh`, after the `git checkout main only ever negated` check for `$AH` (the last agent-handoff SKILL.md check), insert:

```bash
has   "handoff: Launch line rendered"        "Launch:"            "$AH"
has   "handoff: Launch line outside the fence" "outside the fenced prompt block" "$AH"
has   "handoff: luna orchestration bump"     "bumps to Terra"     "$AH"
has   "handoff: recommended base invocation" "recommended base invocation" "$AH"
grep -qE 'gpt-5\.6-luna.*`high`' "$AH" \
  && ok "handoff: visual-validation defaults luna+high on one line" \
  || no "handoff: visual-validation defaults luna+high on one line"
ah_rows="$(grep -E '^\| [SABC] \|' "$AH")"
[ "$(printf '%s\n' "$ah_rows" | grep -c .)" = 4 ] \
  && ok "handoff: ladder has exactly 4 tier rows" \
  || no "handoff: ladder has exactly 4 tier rows (got: $(printf '%s\n' "$ah_rows" | grep -c .))"
[ -n "$orch_rows" ] && [ "$orch_rows" = "$ah_rows" ] \
  && ok "ladder: orchestrator and handoff tables in sync" \
  || no "ladder: orchestrator and handoff tables diverge"
```

(`$orch_rows` is set by Task 1's block earlier in the script; the emptiness guard keeps a missing orchestrator table from comparing equal to a missing handoff table.)

- [ ] **Step 2: Run lint to verify the new checks fail**

Run: `test/lint-skills.sh | grep -E 'FAIL|passed'`
Expected: the 7 new handoff checks FAIL; everything else passes.

- [ ] **Step 3: Add the Launch-line + ladder section**

In `agent-handoff/SKILL.md`, the "Mode and target" section ends with:

```markdown
is unavailable, visual work is blocked; say so instead of downgrading.
```

Immediately after that paragraph, insert:

```markdown
## Model and effort — the Launch line

Every rendered handoff begins with a Launch line addressed to YOU,
the operator, placed outside the fenced prompt block — it is launch advice, never part of
what gets pasted into the executor:

    Launch: Codex.app · gpt-5.6-terra · xhigh   (tier B — same-tier alternative: opus on Claude)

CLI targets get a recommended base invocation instead — you complete repo and prompt transport:
`codex exec -m gpt-5.6-terra -c model_reasoning_effort=xhigh` /
`claude --model opus --effort xhigh`.

| Tier | Claude (`--model`) | Codex (`-m`) | Depth default |
|------|--------------------|--------------|---------------|
| S | `fable` | — | high (xhigh only when capability-limited) |
| A | — | `gpt-5.6-sol` | xhigh |
| B | `opus` | `gpt-5.6-terra` | xhigh |
| C | `sonnet` | `gpt-5.6-luna` | high |

Resolve model and effort from the story's `tier:` × `driver_hint:` against this ladder at render
time — the tier letter governs, not the story's inline comment. An absent `effort:` means the
row's depth default, resolved now; an explicit `effort:` (with its `effort_why:`) wins.
`driver_hint: either` lists both cells. `orchestrate: true` renders ultracode on Claude targets
and `ultra` on the tier's codex model — Luna has no `ultra`, so an orchestrated C-tier codex
story bumps to Terra. A doc without `tier:` (pre-convention): infer a tier from the work's
nature using the grading in `sprint-orchestrator/SKILL.md`, use the current cell default, assume
no orchestration — and say so in the one-line mode/target statement. Never render a blank Launch
line. Depth defaults are operator policy for today's model generation; revisit when a generation
changes.

The Launch line is a recommendation — you decide at paste time. One swap worth knowing: when
Claude capacity is free, a B story can run `fable` at low/medium instead of `opus` at xhigh —
early evidence says that matches for similar burn.
```

- [ ] **Step 4: Grade task mode and re-default visual-validation**

In the "Mode: task (default)" section, append to its paragraph:

```markdown
Grade the work with the ladder's tiers yourself (same grading as the sprint planner) and fold
the pick into the one-line mode/target statement: mode, target, tier, model, effort, why.
```

In "Mode: visual-validation", replace the line:

```markdown
Target is `codex-app`, always. The receiver ends its reply with the test scenario (steps, expected
```

with:

```markdown
Target is `codex-app`, always; the Launch line defaults to `gpt-5.6-luna` · `high` — routine
mechanical driving needs no more (and must not silently inherit a global `ultra` config).
Escalate tier or effort when the ask involves ambiguous design judgment, accessibility review,
or broad multi-surface validation. The receiver ends its reply with the test scenario (steps, expected
```

- [ ] **Step 5: Wire story-execution to the new fields**

In "Mode: story-execution", after the bullet describing `driver_hint:` / `driver_why:`, insert:

```markdown
- `tier:` / `effort:` / `orchestrate:` resolve to the Launch line per the ladder above; render
  the Launch line before the fenced kickoff prompt, never inside it.
```

- [ ] **Step 6: Run lint to verify it passes**

Run: `test/lint-skills.sh | grep -E 'FAIL|passed'`
Expected: `0 failed` — including the ladder-sync check.

- [ ] **Step 7: Commit**

```bash
git branch --show-current && git status --short
git add agent-handoff/SKILL.md test/lint-skills.sh
git commit -m "feat(agent-handoff): render Launch line from tier ladder"
```

---

### Task 3: Orchestration rule in EXECUTION.md

**Files:**
- Modify: `agent-handoff/EXECUTION.md`
- Modify: `test/lint-skills.sh`

**Interfaces:**
- Consumes: nothing new. Produces: the contract rule orchestrated executors follow; no other task depends on it.

- [ ] **Step 1: Add the failing lint check**

In `test/lint-skills.sh`, after the `contract: second interrupt condition` check, insert:

```bash
has   "contract: orchestration never waives the contract" "never waives this contract" "$AHEXEC"
```

Run: `test/lint-skills.sh | grep -E 'FAIL|passed'` — expected: exactly this check FAILs.

- [ ] **Step 2: Add the rule**

In `agent-handoff/EXECUTION.md`, section "## 2. Implement" currently ends with the trailer-block bullet ("…A commit without both is invisible to sprint status."). Append one more bullet to that section:

```markdown
- Orchestration (ultracode / `ultra`) never waives this contract: every commit — including
  commits produced by subagents or workflow stages — carries both trailers, `ownership.owns` /
  `do_not_touch` bind all subagents, and there is a single writer per file at any moment.
```

- [ ] **Step 3: Run lint to verify it passes**

Run: `test/lint-skills.sh | grep -E 'FAIL|passed'`
Expected: `0 failed`.

- [ ] **Step 4: Commit**

```bash
git branch --show-current && git status --short
git add agent-handoff/EXECUTION.md test/lint-skills.sh
git commit -m "feat(agent-handoff): pin orchestration to the execution contract"
```

---

### Task 4: Launch lines in wave-handoffs.sh (fixture-first)

**Files:**
- Create: `sprint-orchestrator/test/test-wave-handoffs.sh`
- Modify: `sprint-orchestrator/wave-handoffs.sh`

**Interfaces:**
- Consumes: frontmatter fields from Task 1 (`tier`, `effort`, `orchestrate`, existing `driver_hint`); the Launch-line format from Task 2: `Launch: <model> · <effort> (tier <T><markers>)`.
- Produces: `launch_line()` bash function inside `wave-handoffs.sh` (takes a story-doc path, prints one Launch line); the fixture test other tasks' verification runs.

- [ ] **Step 1: Write the failing fixture test**

Create `sprint-orchestrator/test/test-wave-handoffs.sh` (mode 755):

```bash
#!/usr/bin/env bash
# test-wave-handoffs.sh — fixture stories in a temp sprint dir; assert rendered Launch lines.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
WH="$HERE/../wave-handoffs.sh"
PASS=0; FAIL=0
ok() { PASS=$((PASS+1)); printf 'ok   - %s\n' "$1"; }
no() { FAIL=$((FAIL+1)); printf 'FAIL - %s\n' "$1"; }
has() { case "$2" in *"$3"*) ok "$1";; *) no "$1 (missing: $3)";; esac; }

SPRINT="$(mktemp -d)/2026-07-10-fixture-sprint"; mkdir -p "$SPRINT"

story() {  # $1=NN $2=slug, remaining args = extra frontmatter lines
  local nn="$1" slug="$2"; shift 2
  { printf -- '---\nstory: %s\ntitle: %s\nconversation: "Story %s: Fixture Case Doc"\n' "$nn" "$slug" "$nn"
    printf 'sprint: 2026-07-10-fixture-sprint\nexecution: stop-at-pr\nflow: mechanical\nloop: direct\nwave: 1\n'
    local line; for line in "$@"; do printf '%s\n' "$line"; done
    printf -- '---\n\n## Objective\nFixture objective %s.\n\n## Goal\n\n/goal fixture goal %s\n' "$nn" "$nn"
  } > "$SPRINT/$nn-$slug.md"
}

story 07 tier-b-codex     'driver_hint: codex'  'tier: B              # opus (claude) / gpt-5.6-terra (codex)' 'tier_why: fixture'
story 08 tier-c-deviation 'driver_hint: claude' 'tier: C' 'tier_why: fixture' 'effort: medium' 'effort_why: fixture sweep'
story 09 tier-b-orch      'driver_hint: codex'  'tier: B' 'tier_why: fixture' 'orchestrate: true'
story 10 tier-c-orch-bump 'driver_hint: codex'  'tier: C' 'tier_why: fixture' 'orchestrate: true'
story 11 legacy-no-tier   'driver_hint: claude'
story 12 tier-b-either    'driver_hint: either' 'tier: B' 'tier_why: fixture'

OUTPUT="$("$WH" "$SPRINT" 1 2>&1)" && ok "wave-handoffs runs" || { no "wave-handoffs runs"; printf '%s\n' "$OUTPUT"; }

has "B/codex resolves terra xhigh"    "$OUTPUT" 'Launch: gpt-5.6-terra · xhigh (tier B)'
has "C/claude deviation renders medium" "$OUTPUT" 'Launch: sonnet · medium (tier C)'
has "orchestrated B/codex is ultra"   "$OUTPUT" 'Launch: gpt-5.6-terra · ultra (tier B)'
has "orchestrated C bumps luna to terra" "$OUTPUT" 'Launch: gpt-5.6-terra · ultra (tier C)'
has "legacy story marks tier unset"   "$OUTPUT" 'tier unset, default B assumed'
has "legacy resolves row B on claude" "$OUTPUT" 'Launch: opus · xhigh (tier B — tier unset, default B assumed)'
has "either lists both cells"         "$OUTPUT" 'Launch: opus · xhigh (claude) or gpt-5.6-terra · xhigh (codex) (tier B)'

in_fence="$(printf '%s\n' "$OUTPUT" | awk '/^```/{f=!f;next} f' | grep -c 'Launch:')"
[ "$in_fence" = 0 ] && ok "no Launch text inside fenced prompts" || no "Launch leaked into a fenced prompt ($in_fence occurrences)"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
```

- [ ] **Step 2: Run the fixture test to verify it fails**

Run: `chmod +x sprint-orchestrator/test/test-wave-handoffs.sh && sprint-orchestrator/test/test-wave-handoffs.sh`
Expected: `wave-handoffs runs` passes (script tolerates unknown frontmatter), all `Launch:` assertions FAIL — the script does not render Launch lines yet.

- [ ] **Step 3: Implement `launch_line()` in wave-handoffs.sh**

In `sprint-orchestrator/wave-handoffs.sh`, after the `goal_line()` definition, insert:

```bash
# ---- Launch line: tier row × driver column, resolved against today's ladder ----
# Keep this table in sync with the ladder in SKILL.md (test-wave-handoffs.sh pins the output).
launch_line() {   # $1 = story doc path -> prints one operator-facing Launch line
  local doc="$1" tier effort orchestrate driver marker="" c_model x_model depth c_eff x_eff
  tier="$(fm_get "$doc" tier)"; effort="$(fm_get "$doc" effort)"
  orchestrate="$(fm_get "$doc" orchestrate)"; driver="$(fm_get "$doc" driver_hint)"
  if [ -z "$tier" ]; then tier="B"; marker=" — tier unset, default B assumed"; fi
  case "$tier" in
    S) c_model="fable";  x_model="";              depth="high"  ;;
    A) c_model="";       x_model="gpt-5.6-sol";   depth="xhigh" ;;
    B) c_model="opus";   x_model="gpt-5.6-terra"; depth="xhigh" ;;
    C) c_model="sonnet"; x_model="gpt-5.6-luna";  depth="high"  ;;
    *) c_model="opus";   x_model="gpt-5.6-terra"; depth="xhigh"
       marker=" — unknown tier '$tier', default B assumed"; tier="B" ;;
  esac
  [ -n "$effort" ] && depth="$effort"
  c_eff="$depth"; x_eff="$depth"
  if [ "$orchestrate" = "true" ]; then
    c_eff="ultracode"; x_eff="ultra"
    [ "$x_model" = "gpt-5.6-luna" ] && x_model="gpt-5.6-terra"   # Luna has no ultra
  fi
  case "$driver" in
    codex)  [ -n "$x_model" ] || { driver="claude"; marker="$marker — driver_hint conflicts with tier S, claude only"; } ;;
    claude) [ -n "$c_model" ] || { driver="codex";  marker="$marker — driver_hint conflicts with tier A, codex only"; } ;;
  esac
  case "$driver" in
    codex)  printf 'Launch: %s · %s (tier %s%s)\n' "$x_model" "$x_eff" "$tier" "$marker" ;;
    claude) printf 'Launch: %s · %s (tier %s%s)\n' "$c_model" "$c_eff" "$tier" "$marker" ;;
    *)  if [ -z "$x_model" ]; then
          printf 'Launch: %s · %s (tier %s%s)\n' "$c_model" "$c_eff" "$tier" "$marker"
        elif [ -z "$c_model" ]; then
          printf 'Launch: %s · %s (tier %s%s)\n' "$x_model" "$x_eff" "$tier" "$marker"
        else
          printf 'Launch: %s · %s (claude) or %s · %s (codex) (tier %s%s)\n' \
            "$c_model" "$c_eff" "$x_model" "$x_eff" "$tier" "$marker"
        fi ;;
  esac
}
```

- [ ] **Step 4: Emit the Launch line in recap and kickoffs**

Still in `wave-handoffs.sh`. In the recap loop, replace:

```bash
  printf -- '- **%s — %s** _(%s, driver: %s)_ — %s\n' "$story" "$title" "$execution" "$driver_hint" "$obj"
```

with:

```bash
  printf -- '- **%s — %s** _(%s, driver: %s)_ — %s\n' "$story" "$title" "$execution" "$driver_hint" "$obj"
  printf -- '  - %s\n' "$(launch_line "$doc")"
```

In the per-story kickoff loop, replace:

```bash
  printf '\n---\n\n## %s — %s\n\n' "$story" "$title"
  printf '```\n'
```

with:

```bash
  printf '\n---\n\n## %s — %s\n\n' "$story" "$title"
  printf '**%s**\n\n' "$(launch_line "$doc")"
  printf '```\n'
```

Also update the generated-doc preamble: replace the sentence fragment

```bash
printf '`agent-handoff` (story-execution) kickoff — paste each into its own executor session. `driver_hint` is the '
printf 'affinity default; capability, your explicit choice, and current availability override it at paste time. The '
```

with:

```bash
printf '`agent-handoff` (story-execution) kickoff — paste each into its own executor session. The **Launch** line above '
printf 'each block is a recommendation resolved from the story'"'"'s tier and driver; capability, your explicit choice, and '
printf 'current availability override it at paste time. The '
```

- [ ] **Step 5: Run the fixture test to verify it passes**

Run: `sprint-orchestrator/test/test-wave-handoffs.sh`
Expected: PASS, `0 failed` — including `no Launch text inside fenced prompts`.

- [ ] **Step 6: Run the neighboring test suites**

Run: `sprint-orchestrator/test/test-sprint-status.sh && test/lint-skills.sh | tail -1`
Expected: sprint-status suite passes (untouched); lint `0 failed`.

- [ ] **Step 7: Commit**

```bash
git branch --show-current && git status --short
git add sprint-orchestrator/wave-handoffs.sh sprint-orchestrator/test/test-wave-handoffs.sh
git commit -m "feat(sprint-orchestrator): render Launch lines in wave-handoffs"
```

---

### Task 5: README updates + full verification

**Files:**
- Modify: `sprint-orchestrator/README.md`

**Interfaces:**
- Consumes: everything above. Produces: nothing downstream — final documentation + verification gate.

- [ ] **Step 1: Update the wave-handoffs README section**

In `sprint-orchestrator/README.md`, section "## Render a wave's handoffs", replace:

```markdown
Each kickoff mirrors `agent-handoff/SKILL.md`'s story-execution template — that skill file is the
source of truth for the shape; this script fills it in. `execution:` → the EXECUTION MODE line,
`loop:` → the planning-depth line, `driver_hint:` → the affinity default and the EXECUTION.md path
(`~/.codex` vs `~/.claude`); capability, your explicit say, and current availability still override
the driver at paste time. It expects the current frontmatter (`conversation`/`execution`/`loop`/
`driver_hint`); pre-convention docs render with those fields blank. Exit code 2 on a bad sprint
directory or a wave with no stories.
```

with:

```markdown
Each kickoff mirrors `agent-handoff/SKILL.md`'s story-execution template — that skill file is the
source of truth for the shape; this script fills it in. `execution:` → the EXECUTION MODE line,
`loop:` → the planning-depth line, `driver_hint:` → the affinity default and the EXECUTION.md path
(`~/.codex` vs `~/.claude`); `tier:` + `effort:`/`orchestrate:` → the **Launch** line (model ·
effort) printed above each fenced block, resolved against the ladder in the SKILL.md files.
Capability, your explicit say, and current availability still override everything at paste time.
It expects the current frontmatter (`conversation`/`execution`/`loop`/`driver_hint`/`tier`); docs
without `tier:` render a row-B default with an explicit "tier unset" marker. Exit code 2 on a bad
sprint directory or a wave with no stories.
```

- [ ] **Step 2: Run every suite**

Run: `test/lint-skills.sh | tail -1 && sprint-orchestrator/test/test-sprint-status.sh | tail -1 && sprint-orchestrator/test/test-wave-handoffs.sh | tail -1 && codex/test/test.sh | tail -1`
Expected: four `… 0 failed` lines.

- [ ] **Step 3: Commit**

```bash
git branch --show-current && git status --short
git add sprint-orchestrator/README.md
git commit -m "docs(sprint-orchestrator): document tier inputs and Launch output"
```
