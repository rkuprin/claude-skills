# Model-Tier + Effort Routing Across sprint-orchestrator, agent-handoff, codex — Design

- **Date:** 2026-07-10
- **Repo:** `~/claude-skills` (shared skills, symlinked into `~/.claude/skills` and `~/.codex/skills`)
- **Status:** draft, pending user review
- **Builds on:** `2026-07-10-model-aware-sprint-planning-design.md` (driver_hint, agent-handoff
  modes, late driver binding — all shipped and untouched here)

## Context

The shipped design routes work by *harness affinity* (`driver_hint: codex|claude|either`) but is
silent on *capability tier* and *effort*. Meanwhile:

- Multiple models per harness are in play: Claude Code runs Fable 5 / Opus 4.8 / Sonnet 5; Codex
  runs GPT-5.6 Sol / Terra / Luna (GA 2026-07-09).
- Effort is a real knob on both sides. The installed codex binary (0.144.1) accepts
  `low|medium|high|xhigh|max|ultra` for `model_reasoning_effort` (verified via strings on the
  binary); `claude` accepts `--effort <level>` and `--model <alias>`.
- Orchestration modes exist on both sides: ultracode (Claude Code harness setting: xhigh + dynamic
  workflow orchestration) and `ultra` (Codex effort value, Sol-only, subagent fan-out).
- Today nothing scales cost to the work: the codex reviewer skill pins `gpt-5.6-sol`; the user's
  global `~/.codex/config.toml` runs `model_reasoning_effort = "ultra"`, which visual-validation
  handoffs silently inherit; story docs carry no tier or effort at all.

Problems this design addresses:

1. Sprint planning should run at maximum capability and *grade* each story so cheaper models and
   efforts execute whatever they can.
2. agent-handoff renders prompts but never tells the operator which model/effort to launch.
3. The codex reviewer burns Sol at high/ultra for every run, including contained ones.

## Decisions locked during brainstorm

- **Tier composes with driver_hint; it does not replace it.** `tier: S|A|B|C` grades difficulty
  (capability floor); `driver_hint` stays affinity. Tier picks the ladder row, driver picks the
  column. S and A determine the harness by themselves (S → Claude/Fable, A → Codex/Sol); a
  contradictory pair (e.g. `tier: S` + `driver_hint: codex`) is a planning error.
- **Tier resolution is noted inline** in the story frontmatter comment (e.g.
  `tier: B  # opus (claude) / gpt-5.6-terra (codex)`) so a story doc reads standalone. The tier
  letter governs; the comment is advisory and re-resolved against the current ladder at handoff.
- **`effort:` is written per story, always** — but its default comes from the ladder row, not a
  blanket value (amended from "always xhigh" after the effort-calibration evidence below).
  Deviating from the row default needs a one-line why.
- **The operator holds final judgment.** Handoffs are prompts the user copies and pastes; the
  skill renders a recommendation (a Launch line), never enforcement. No floor/pin machinery, no
  availability automation.
- **codex reviewer scales both model and effort by scope.** Two lanes; floor is Terra — never
  Luna, because independent judgment is the product. `--model`/`--effort` still override.
- **Only current models appear in skill prose.** Ladder cells are the exact launch values
  (`--model` aliases on Claude, which track the latest model; real slugs on Codex, which has no
  alias mechanism). Old-model nuances live only in this spec's evidence appendix.

## The ladder (canonical, duplicated verbatim in both SKILL.md files, linted for sync)

| Tier | Claude (`--model`) | Codex (`-m`) | Depth default |
|------|--------------------|--------------|---------------|
| S | `fable` | — | high (xhigh only when capability-limited) |
| A | — | `gpt-5.6-sol` | xhigh |
| B | `opus` | `gpt-5.6-terra` | xhigh |
| C | `sonnet` | `gpt-5.6-luna` | high |

Shared depth scale, literal on both harnesses: `low | medium | high | xhigh | max`. Orchestration
is a separate axis, not a depth: ultracode (Claude) / `ultra` (Codex, Sol-only) — for
coverage-shaped, fire-and-verify work only.

Maintenance note accompanying the table: depth defaults are calibrated against today's model
generation; effort levels do not port across models — revisit the defaults when a generation
changes.

Grading guidance (sprint-orchestrator prose):

- **S** — ambiguous, architectural, novel design; a wrong turn is very expensive.
- **A** — hard but well-scoped cross-cutting work, mechanistic-leaning (Sol is the Codex column).
- **B** — multi-file but well-trodden.
- **C** — contained mechanical work; most `loop: direct` stories.

Like `driver_hint`, `tier:` derives from the work's nature only — never from today's capacity.

## sprint-orchestrator changes

1. **Strongest-model gate gains effort.** Planning runs Fable at max effort — ultracode welcome
   for the research/verification sweep — else Opus; Sol at ultra on Codex (current prose already
   names Sol/ultra). Same name-your-model + offer-to-stop behavior; a lesser model still needs the
   user's recorded go-ahead in `00-overview.md`.
2. **Ladder + grading guidance** added as a short section (the canonical table above).
3. **Story frontmatter delta** (template gains four fields; everything else unchanged):

   ```yaml
   tier: B              # opus (claude) / gpt-5.6-terra (codex)
   tier_why: multi-file but well-trodden
   effort: xhigh        # row default; deviating needs a why
   orchestrate: true    # optional — write only when true; see criterion
   ```

   `orchestrate: true` criterion: the story itself is coverage-shaped and fire-and-verify — an
   audit, a migration, a repo-wide sweep where missing something costs more than compute.
   Interactive/redirectable work never gets it (dynamic workflows cannot pause for input). On a
   Codex driver it implies Sol regardless of tier, since `ultra` is Sol-only.

## agent-handoff changes

1. **Ladder duplicated verbatim** (repo rule: no cross-file "see the convention over there"),
   plus the resolution note: tier row × driver column at render time; the operator decides.
2. **Launch line, rendered above the prompt, addressed to the operator** — every mode:

   ```
   Launch: Codex.app · gpt-5.6-terra · xhigh   (tier B — same-tier alternative: opus on Claude)
   ```

   CLI targets render ready-to-run commands instead:
   `codex exec -m gpt-5.6-terra -c model_reasoning_effort=xhigh …` /
   `claude --model opus --effort xhigh …`. `driver_hint: either` lists both cells.
3. **story-execution** reads `tier:` / `effort:` / `orchestrate:` from the story doc frontmatter
   and resolves against the ladder at render time (the letter governs, not the story's inline
   comment). `orchestrate: true` renders as ultracode (Claude targets) / Sol + `ultra` (Codex
   targets) in the Launch line.
4. **task mode** grades the work itself using the same guidance and names the (tier, model,
   effort) pick in its existing one-line mode/target statement.
5. **visual-validation defaults to `gpt-5.6-luna` at `high`** — mechanical browser-driving; today
   it silently inherits the global `ultra` config. The user's explicit say overrides. Target
   remains `codex-app` always (capability rule unchanged).
6. **Operator swap note** (handoff only, not the planner): early evidence suggests Fable at
   low/medium matches or beats Opus at xhigh for similar burn — when Claude capacity is free, the
   operator may swap a B story to Fable at reduced effort. Advice, not a routing rule.

## codex skill changes

1. **Two lanes replace the pinned model** (SKILL.md step 1 rewrite):
   - *Contained* (focused spec, single feature, data claim) → `gpt-5.6-terra`, `xhigh`.
   - *Premise-critical* (architecture, spec→plan gate, cross-cutting, wrong-premise-is-expensive)
     → `gpt-5.6-sol`, `xhigh`. The automatic spec→plan hook path is premise-critical by
     definition.
   - Escalation, depth before orchestration: `sol` + `max` for a single deep chain; `sol` +
     `ultra` only for coverage-shaped review of a big surface. Either needs a one-line
     justification relayed to the user.
   - Floor is Terra — never Luna. `--model` / `--effort` args still override everything.
2. **The skill always passes `--model` and `--effort` explicitly** to `run-codex.sh`.
3. **`run-codex.sh`**: usage text updates to the new effort vocabulary (`xhigh` default,
   `low|medium|high|xhigh|max|ultra` accepted); default `effort="xhigh"`. No logic change — the
   wrapper already passes effort through. `CHARTER.md` untouched.

## Untouched

`EXECUTION.md` (model/effort are launch-time concerns, not executor-contract concerns);
`CHARTER.md`; `sprint-status.sh`, trailers, and state derivation; task-file format; the
`~/.handoffs` convention.

## Lint changes (`test/lint-skills.sh`)

- **Ladder sync**: extract the four tier rows from `sprint-orchestrator/SKILL.md` and
  `agent-handoff/SKILL.md` and diff them (bash + grep/diff dialect only).
- Orchestrator: `has tier:`, `has tier_why:`, `has effort:`, `has orchestrate:`; pins the
  tier-from-nature rule alongside the existing driver_hint one.
- agent-handoff: pins the Launch line, the visual-validation `luna` + `high` default, and the
  `ultra`-is-Sol-only note.
- codex: pins both lanes (`terra`, `sol`, `xhigh`), the Terra floor, and the escalation
  justification requirement; `run-codex.sh` usage mentions `xhigh`.
- `codex/test/test.sh` reviewed for pinned defaults (model/effort) and updated in the same
  commit.

## READMEs

Check the three skill READMEs plus the repo README for stale descriptions of model/effort
behavior; update only lines this change makes wrong.

## Evidence appendix (as of 2026-07-10)

Verified locally:

- codex 0.144.1 binary embeds the reasoning-effort enum `low|medium|high|xhigh|max|ultra`
  (strings inspection); `claude` CLI exposes `--effort <level>` and `--model <alias>`.
- `~/.codex/config.toml` currently sets `model_reasoning_effort = "ultra"` globally — the
  motivating example for explicit per-run effort.

Adopted from the research report (external, sourced from vendor docs + analyses):

- Ultracode is a harness setting, not an effort level: xhigh to the model + dynamic workflow
  orchestration. Depth and orchestration are separate axes.
- Effort scales are calibrated per model; the same level name is not the same underlying value
  across models. Hence per-row depth defaults instead of one blanket default.
- Fable effort inversion: Fable@low ≈ 75.0 vs Opus 4.8@xhigh ≈ 68.6 on SWE-bench Pro at roughly
  half the per-task cost (vendor system-card numbers; agentic-coding benchmarks only). Encoded
  conservatively as: S-row default `high` (matches Anthropic's start-at-high guidance) + the
  operator swap note in agent-handoff.
- GPT-5.6 GA 2026-07-09: Sol/Terra/Luna; `max` = deepest single chain; `ultra` = subagent
  orchestration, Sol-only.

Watch-items (deliberately NOT adopted; revisit when independent numbers land):

- Restructuring the tiers around the inversion (e.g. "Fable@low" replacing Opus in row B) — one
  vendor benchmark, no independent replication, unknown transfer beyond agentic coding.
- Standardizing Codex `ultra` anywhere — ~1 day old, vendor-only benchmarks (Terminal-Bench 2.1:
  Sol max 88.8 vs ultra 91.9), and METR flagged Sol for record-rate benchmark gaming.

## Risks

- **Ladder drift between the two SKILL.md copies** — mitigated by the sync lint.
- **Stale inline resolution comments** in old story docs after a ladder edit — the tier letter
  governs at handoff; the comment is advisory by design.
- **Depth defaults go stale** when a model generation changes — maintenance note pinned next to
  the table; the evidence appendix records what they were calibrated against.

## Success criteria

- `test/lint-skills.sh`, `codex/test/test.sh`, `sprint-orchestrator/test/test-sprint-status.sh`
  all pass, including the new checks.
- The story template shows `tier` / `tier_why` / `effort` / `orchestrate` with the inline
  resolution comment shape.
- A rendered story-execution handoff for a B/codex story carries a Launch line naming
  `gpt-5.6-terra` + `xhigh`; a visual-validation handoff names `gpt-5.6-luna` + `high`.
- The codex skill run with no flags on a contained goal composes a Terra + xhigh invocation; the
  spec→plan hook path composes Sol + xhigh.
