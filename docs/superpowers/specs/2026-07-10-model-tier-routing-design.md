# Model-Tier + Effort Routing Across sprint-orchestrator, agent-handoff, codex — Design

- **Date:** 2026-07-10 (amended same day after independent Codex review)
- **Repo:** `~/claude-skills` (shared skills, symlinked into `~/.claude/skills` and `~/.codex/skills`)
- **Status:** approved design, review amendments folded in
- **Builds on:** `2026-07-10-model-aware-sprint-planning-design.md` (driver_hint, agent-handoff
  modes, late driver binding — shipped). This spec **explicitly supersedes** one part of it:
  for tiers S and A the harness is bound at plan time by the tier choice itself; late driver
  binding continues to apply to tiers B and C. Everything else in the prior design stands.

## Context

The shipped design routes work by *harness affinity* (`driver_hint: codex|claude|either`) but is
silent on *capability tier* and *effort*. Meanwhile:

- Multiple models per harness are in play: Claude Code runs Fable 5 / Opus 4.8 / Sonnet 5; Codex
  runs GPT-5.6 Sol / Terra / Luna — available in this operator's Codex workspace as of
  2026-07-10 (vendor status: preview per OpenAI's availability page; not claimed GA).
- Effort is a real knob on both sides. The installed codex binary (0.144.1) accepts
  `low|medium|high|xhigh|max|ultra` for `model_reasoning_effort` (verified in the binary), and
  the workspace model cache (`codex/codex-home/models_cache.json`) confirms per-model support:
  Sol and Terra list `ultra`; **Luna tops out at `max`**. `claude` accepts `--effort <level>`
  and `--model <alias>`.
- Orchestration modes exist on both sides: ultracode (Claude Code harness setting: xhigh + dynamic
  workflow orchestration) and `ultra` (Codex effort value — supported by Sol *and* Terra).
- Today nothing scales cost to the work: the codex reviewer skill pins `gpt-5.6-sol`; the user's
  global `~/.codex/config.toml` runs `model_reasoning_effort = "ultra"`, which visual-validation
  handoffs silently inherit; story docs carry no tier or effort at all; and the deterministic
  wave renderer (`sprint-orchestrator/wave-handoffs.sh`) reads only `driver_hint`.

Problems this design addresses:

1. Sprint planning should run at maximum capability and *grade* each story so cheaper models and
   efforts execute whatever they can.
2. agent-handoff (and the wave renderer that mirrors it) never tells the operator which
   model/effort to launch.
3. The codex reviewer burns Sol for every run, including contained ones.

## Decisions locked during brainstorm and review

- **Tiers are routing presets, not an empirical capability ordering.** The S/A/B/C ladder is the
  operator's chosen policy for what grade of work goes to which model. Tier grades difficulty;
  `driver_hint` stays affinity. Tier picks the ladder row, driver picks the column. S and A have
  one cell each, so they bind the harness at plan time (superseding late binding for those
  tiers); for S/A, `driver_hint` must equal the tier's harness (S → `claude`, A → `codex`) and
  `either` is invalid there. A contradictory pair (e.g. `tier: S` + `driver_hint: codex`) is a
  planning error.
- **Tier resolution is noted inline** in the story frontmatter comment (e.g.
  `tier: B  # opus (claude) / gpt-5.6-terra (codex)`). The tier letter governs; the comment is
  advisory and re-resolved against the current ladder at render time.
- **Effort is written only on deviation** (amended after review — materialized defaults go
  stale). A story inheriting its ladder-row default has **no** `effort:` field; the renderer
  resolves it against the current ladder. A deviating story writes `effort:` **and** a required
  `effort_why:` line. Overrides therefore stay distinguishable from defaults across ladder
  edits.
- **Depth defaults are operator policy, not vendor calibration.** The workspace model cache
  defaults Sol to `low` and Terra/Luna to `medium`; this ladder deliberately runs hotter.
  Per-row (not per-cell) defaults are a deliberate policy simplification.
- **The operator holds final judgment.** Handoffs are prompts the user copies and pastes; the
  skill renders a recommendation (a Launch line), never enforcement. Any deviation — up, down,
  or sideways — is the operator's call at paste time. No availability automation.
- **codex reviewer scales both model and effort by scope.** Two lanes with explicit precedence;
  floor is Terra — never Luna, because independent judgment is the product.
- **Only current models appear in skill prose.** Ladder cells are the exact launch values
  (`--model` aliases on Claude, which track the latest model; real slugs on Codex, which has no
  alias mechanism). Old-model nuances live only in this spec's evidence appendix.
- **Two implementation plans**, not one: (1) sprint/handoff routing (schema, tier semantics,
  effort inheritance, Launch output, `wave-handoffs.sh` + fixture test, backward compatibility,
  EXECUTION.md orchestration rules, READMEs, lint); (2) codex reviewer cost routing (lanes,
  flag propagation, wrapper default, resume, tests, README). Independent behavior, rollout
  risk, and verification.

## The ladder (canonical, duplicated verbatim in both SKILL.md files, linted for sync)

| Tier | Claude (`--model`) | Codex (`-m`) | Depth default |
|------|--------------------|--------------|---------------|
| S | `fable` | — | high (xhigh only when capability-limited) |
| A | — | `gpt-5.6-sol` | xhigh |
| B | `opus` | `gpt-5.6-terra` | xhigh |
| C | `sonnet` | `gpt-5.6-luna` | high |

Shared depth scale, literal on both harnesses: `low | medium | high | xhigh | max`.

**Orchestration** is a separate concept but not a separate launch control: it occupies the same
setting as depth (Codex: `model_reasoning_effort=ultra`; Claude: ultracode, which implies xhigh).
Legal-combination rule: `orchestrate: true` **implies xhigh depth**; a story writing both
`orchestrate: true` and an `effort:` value is invalid. On Codex, Sol and Terra orchestrate
(`ultra`); a C-tier codex story that needs orchestration bumps to Terra. On Claude, ultracode is
the toggle. The flag maps to whichever orchestration feature the harness currently offers.

Maintenance note accompanying the table: depth defaults are the operator's policy for today's
model generation; effort levels do not port across models — revisit when a generation changes.

Grading guidance (sprint-orchestrator prose):

- **S** — ambiguous, architectural, novel design; a wrong turn is very expensive.
- **A** — hard but well-scoped cross-cutting work, mechanistic-leaning (Sol is the Codex column).
- **B** — multi-file but well-trodden.
- **C** — contained mechanical work; most `loop: direct` stories.

Like `driver_hint`, `tier:` derives from the work's nature only — never from today's capacity.

## sprint-orchestrator changes

1. **Strongest-model gate names the orchestration mode.** Sprint planning is coverage-shaped
   (verify every candidate against source truth), so it runs the orchestration mode on the
   strongest model: Fable with ultracode on Claude Code, else Opus with ultracode; Sol at
   `ultra` on Codex. Same name-your-model + offer-to-stop behavior; a lesser model still needs
   the user's recorded go-ahead in `00-overview.md`.
2. **Ladder + grading guidance** added as a short section (the canonical table above).
3. **Story frontmatter delta** (template gains these fields; everything else unchanged):

   ```yaml
   tier: B              # opus (claude) / gpt-5.6-terra (codex)
   tier_why: multi-file but well-trodden
   # effort/effort_why: ONLY when deviating from the row default
   # orchestrate: true  # ONLY when true; implies xhigh; never combined with effort:
   ```

   Deviation example:

   ```yaml
   tier: C              # sonnet (claude) / gpt-5.6-luna (codex)
   tier_why: contained mechanical rename
   effort: medium
   effort_why: pure mechanical sweep, low ambiguity
   ```

   `orchestrate: true` criterion: the story itself is coverage-shaped and fire-and-verify — an
   audit, a migration, a repo-wide sweep where missing something costs more than compute.
   Interactive/redirectable work never gets it (dynamic workflows cannot pause for input).

## agent-handoff changes

1. **Ladder duplicated verbatim** (repo rule: no cross-file "see the convention over there"),
   plus the resolution note: tier row × driver column at render time; the operator decides.
2. **Launch line, rendered OUTSIDE the fenced paste block, addressed to the operator** — every
   mode. It must never end up inside the prompt the executor reads:

   ```
   Launch: Codex.app · gpt-5.6-terra · xhigh   (tier B — same-tier alternative: opus on Claude)
   ```

   CLI targets get a **recommended base invocation** (the operator completes repo/prompt
   transport): `codex exec -m gpt-5.6-terra -c model_reasoning_effort=xhigh` /
   `claude --model opus --effort xhigh`. `driver_hint: either` lists both cells (B/C only —
   `either` is invalid for S/A).
3. **story-execution** reads `tier:` / `effort:` / `effort_why:` / `orchestrate:` from the story
   doc and resolves against the ladder at render time (the letter governs, not the story's
   inline comment; absent `effort:` means the current row default). `orchestrate: true` renders
   as ultracode (Claude targets) / `ultra` on the tier's codex model, bumping Luna to Terra
   (Codex targets).
4. **Old story docs** (no tier/effort fields): the skill infers a tier from the grading
   guidance, uses the current cell default, assumes no orchestration — and says so in its
   one-line mode/target statement. A blank Launch line is not acceptable output.
5. **task mode** grades the work itself using the same guidance and names the (tier, model,
   effort) pick in its existing one-line mode/target statement.
6. **visual-validation defaults to `gpt-5.6-luna` at `high`** for routine mechanical checks —
   today it silently inherits the global `ultra` config. Escalation triggers, named in prose:
   ambiguous design judgment, accessibility review, or broad multi-surface validation warrant a
   higher tier or effort. The user's explicit say overrides. Target remains `codex-app` always
   (capability rule unchanged).
7. **Operator swap note** (handoff only, not the planner): early evidence suggests Fable at
   low/medium can match Opus at xhigh for similar burn — when Claude capacity is free, the
   operator may swap a B story to Fable at reduced effort. Advice, not a routing rule.

## wave-handoffs.sh changes (deterministic renderer — was missing from the original scope)

`sprint-orchestrator/wave-handoffs.sh` mirrors agent-handoff's story-execution template and must
stay in sync (its header says so). It gains:

- Frontmatter parsing for `tier`, `effort`, `effort_why`, `orchestrate` via the existing
  `fm_get` helper (comment-stripping already handles the inline resolution comments).
- A ladder table encoded in the script (case statement), resolving (tier, driver_hint) → model +
  depth default; explicit `effort:` overrides the default; `orchestrate: true` → ultracode note
  (claude) / `ultra` with Luna→Terra bump (codex).
- A Launch line per story, emitted in the recap section and above each fenced block — **never
  inside the fence**, so it cannot leak into the executor prompt.
- Backward compatibility: `tier` absent → render row B's cell default for the story's driver
  with an explicit `(tier unset — default B assumed)` marker, no orchestration. Never emit a
  blank Launch line.
- A new fixture-based test `sprint-orchestrator/test/test-wave-handoffs.sh` (bash + grep
  dialect): fixture story docs covering tiered/deviating/orchestrated/legacy cases, asserting
  the rendered Launch lines and that fenced blocks contain no Launch text.

## codex skill changes

1. **Two lanes replace the pinned model** (SKILL.md step 1 rewrite), with explicit precedence —
   consequence outranks artifact size:
   1. An explicit `--model` / `--effort` from the caller wins.
   2. The automatic spec→plan hook path is premise-critical by definition.
   3. Stakes: if a wrong premise is expensive (architecture, cross-cutting change, a data claim
      that underpins a big decision) → premise-critical, even when the artifact is small.
   4. Otherwise contained.
   - *Contained* → `gpt-5.6-terra`, `xhigh`. *Premise-critical* → `gpt-5.6-sol`, `xhigh`.
   - Escalation, depth before orchestration: `sol` + `max` for a single deep chain; `sol` +
     `ultra` only for coverage-shaped review of a big surface. Either requires a one-line
     justification **stated to the user before the run spends the compute**.
   - Floor is Terra — never Luna.
2. **The skill always passes `--model` and `--effort` explicitly** — on `run` *and* `resume`.
3. **`run-codex.sh`**: usage text updates to the new effort vocabulary
   (`low|medium|high|xhigh|max|ultra`); default `effort="xhigh"`. No logic change. `CHARTER.md`
   untouched.
4. **`codex/test/test.sh`**: add a case that omits `--effort` and asserts the wrapper default
   (`xhigh`) reaches the fake codex; existing explicit-effort cases stay. Lane classification is
   LLM judgment — grep cannot test it; it is pinned instead as a named manual acceptance
   scenario in the plan (run the skill on a contained goal, observe Terra+xhigh composed).
5. **`codex/README.md`**: required edits, not opportunistic — the posture line currently says
   "model inherited (no `-m`)", which is already stale (the wrapper pins Sol today) and becomes
   wrong twice over with lanes. Rewrite to describe lane selection and the Terra floor.

## EXECUTION.md change (one short addition)

Orchestrated execution gets a hard rule in the Implement section: orchestration never waives the
contract — every commit still carries both trailers (including commits produced by subagents or
workflow stages), `ownership.owns` / `do_not_touch` bind all subagents, and there is a single
writer per file at any moment. Everything else in EXECUTION.md is untouched (model/effort remain
launch-time concerns).

## Untouched

`CHARTER.md`; `sprint-status.sh`, trailers, and state derivation; task-file format; the
`~/.handoffs` convention.

## Lint changes (`test/lint-skills.sh`)

- **Ladder sync**: extract the four tier rows from `sprint-orchestrator/SKILL.md` and
  `agent-handoff/SKILL.md`, assert **exactly four rows in each file** (two missing tables must
  not compare equal), then diff (bash + grep/diff dialect).
- Checks are relational and anchored where possible: e.g. `gpt-5.6-luna` and `high` asserted on
  the same line in the visual-validation prose; frontmatter fields (`tier:`, `tier_why:`,
  `effort_why:`, `orchestrate:`) matched against the template block, not incidental prose.
- Orchestrator: pins the tier-from-nature rule alongside the existing driver_hint one; pins the
  effort-only-on-deviation rule and the orchestrate-implies-xhigh rule.
- agent-handoff: pins the Launch-line-outside-the-fence rule and the Luna→Terra orchestration
  bump.
- codex: pins both lanes (`terra`, `sol`, `xhigh`), the Terra floor, the
  justification-before-spending rule; `run-codex.sh` usage mentions `xhigh`.
- Rendering correctness is established by `test-wave-handoffs.sh` fixtures, not by lint.

## READMEs

- `codex/README.md`: required rewrite of the posture paragraph (see above).
- `sprint-orchestrator/README.md`: wave-handoffs section documents the new frontmatter inputs
  and the Launch-line output.
- `agent-handoff/README.md` + repo `README.md`: update only lines this change makes wrong.

## Evidence appendix (as of 2026-07-10)

Verified locally:

- codex 0.144.1 binary embeds the reasoning-effort enum `low|medium|high|xhigh|max|ultra`
  (strings inspection); `claude` CLI exposes `--effort <level>` and `--model <alias>`.
- `codex/codex-home/models_cache.json`: Sol supports `low…ultra` (vendor default `low`); Terra
  supports `low…ultra` (default `medium`); **Luna supports `low…max`, no `ultra`** (default
  `medium`). So orchestration on Codex is Sol *or* Terra; and the ladder's xhigh policy runs
  hotter than vendor defaults by choice.
- `~/.codex/config.toml` currently sets `model_reasoning_effort = "ultra"` globally — the
  motivating example for explicit per-run effort.

Adopted from the research report (external), with review corrections:

- Ultracode is a harness setting, not an effort level: xhigh to the model + dynamic workflow
  orchestration. Depth and orchestration are conceptually separate but share one launch control.
- Effort scales differ per model; level names do not port across models.
- Effort inversion: the top-tier model at low effort outscored Opus 4.8 at xhigh (≈75.0 vs
  ≈68.6, SWE-bench Pro) at roughly half the per-task cost — **benchmarked on Mythos 5, which
  shares the underlying model with Fable 5 but lacks its safeguards; agentic-coding benchmarks
  only.** Encoded conservatively as: S-row default `high` (matches Anthropic's start-at-high
  guidance) + the operator swap note in agent-handoff.
- GPT-5.6 Sol/Terra/Luna available in this operator's workspace as of 2026-07-10; vendor status
  preview, no GA claim. `max` = deepest single chain; `ultra` = subagent orchestration.

Watch-items (deliberately NOT adopted; revisit when independent numbers land):

- Restructuring the tiers around the inversion (e.g. "Fable@low" replacing Opus in row B) — one
  vendor benchmark, no independent replication, unknown transfer beyond agentic coding.
- Standardizing Codex `ultra` anywhere — vendor-only benchmarks (Terminal-Bench 2.1: Sol max
  88.8 vs ultra 91.9) and a METR report flagging Sol for record-rate benchmark gaming.

## Risks

- **Ladder drift between the two SKILL.md copies and the script's encoded table** — mitigated by
  the sync lint (SKILL.md × SKILL.md) and the fixture test (script × expected output).
- **Stale inline resolution comments** in old story docs after a ladder edit — the tier letter
  governs at render time; the comment is advisory by design; effort staleness is designed out
  (only deviations are written).
- **Depth defaults go stale** when a model generation changes — maintenance note pinned next to
  the table; the evidence appendix records what they were set against.
- **Launch-line leakage into executor prompts** — pinned by lint (prose rule) and asserted by
  the wave-handoffs fixture test (no Launch text inside fences).

## Success criteria

- `test/lint-skills.sh`, `codex/test/test.sh`, `sprint-orchestrator/test/test-sprint-status.sh`,
  and the new `sprint-orchestrator/test/test-wave-handoffs.sh` all pass.
- The story template shows `tier` / `tier_why` with the inline resolution comment shape;
  `effort`+`effort_why` appear only in the deviation example; `orchestrate` documented as
  implying xhigh.
- `wave-handoffs.sh` renders: a B/codex story → Launch line naming `gpt-5.6-terra` + `xhigh`
  outside the fence; an orchestrated B/codex story → `gpt-5.6-terra` + `ultra`; a legacy story
  without tier → row-B default with the `(tier unset)` marker; never a blank Launch line.
- A visual-validation handoff names `gpt-5.6-luna` + `high` and lists the escalation triggers.
- The codex skill run with no flags on a contained goal composes a Terra + xhigh invocation; the
  spec→plan hook path composes Sol + xhigh; resume carries the same explicit flags.
