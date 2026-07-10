# Model-Aware Sprint Planning + Unified Agent Handoff — Design

- **Date:** 2026-07-10 (amended same day after independent Codex review)
- **Repo:** `~/claude-skills` (shared skills, symlinked into `~/.claude/skills` and `~/.codex/skills`)
- **Status:** approved design, review amendments folded in

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

## Decisions locked during brainstorm and review

- **Late driver binding.** The planner records a per-story driver *hint* derived **only from the
  work's nature** (capacity is recorded separately as plan-time context); the final driver is
  resolved at handoff time. Resolution precedence, in one line: required capability → the user's
  explicit say → current availability → affinity. Beyond that, judgment — no rigid algorithm.
- **One handoff skill.** New `agent-handoff` with three modes; `codex-execution-handoff` retires via
  the migration order below (git history keeps the prose).
- **No driver registry.** Model personalities are a one-two line heuristic inside the skill; the
  judgment stays with the running model and the user. No model catalog to maintain.
- **Playbook doc + inline hard rules.** The lifecycle contract moves to `agent-handoff/EXECUTION.md`.
  Unlike the `/codex` skill's CHARTER.md (auto-loaded via CODEX_HOME), EXECUTION.md is merely
  *referenced* by the prompt — a doc is followed less reliably than pasted text. Therefore the
  catastrophic-if-missed rules stay inline in the prompt, with literal values, not placeholders.
- **`/goal` is universal** (user decision). It is a command in both Codex.app and Claude Code, and
  in a CLI one-shot it reads as plain text that still carries the goal. Every rendered prompt ends
  with `/goal` regardless of target. Do not re-flag this.
- **`loop:` is planning depth, not lifecycle.** Every numbered sprint story — `full` or `direct` —
  runs the full story-execution contract (claim, branch, trailers, ownership, gates, feedback).
  Generic task mode is reserved for work *outside* the sprint ledger.
- **Visual validation is report-only by default.** Fixing is an explicit grant, never implied.

## sprint-orchestrator changes

All additive prose + frontmatter; state derivation (`sprint-status.sh`, trailers) is untouched.

1. **Planner model gate** (new ~3-line section). Sprint planning runs on the most capable model
   available. At session start the planner names the model it is running as; if that is not the
   strongest tier reachable right now (today: Fable, else Opus, on Claude Code; Sol at ultra effort
   on Codex), it says so and offers to stop so the user can relaunch. No hard block, but proceeding
   on a lesser model requires the user's explicit go-ahead, recorded in `00-overview.md`.
2. **Planning philosophy** (new paragraph in Plan Session). This skill does high-level planning
   backed by in-depth research; it does not write per-story implementation plans. `loop: full`
   (default): the story's execution session runs its own self-directed brainstorm → spec → plan →
   execute phases — the agent's own loop under the story's single late `/goal` checkpoint, not the
   user-gated brainstorming workflow. `loop: direct`: the story is simple enough to define fully at
   plan time; the executor skips straight to a short TDD plan, and the story may be delegated to a
   cheaper transport (subagent, `codex exec`, `claude -p`). Either way the lifecycle contract is
   identical — `loop:` never waives trailers, branch discipline, or gates.
3. **Driver awareness** (two-line heuristic, verbatim spirit): *Codex leans mechanistic, devops, and
   browser-driving work; Claude leans creative, frontend-heavy, ambiguous work. Frontend visual
   validation renders only in Codex.app.* Capability constraints outrank affinity: a frontend story
   implemented on Claude still ends with a visual-validation handoff to Codex.app — affinity routes
   *stages*, not just whole stories. Anything past that is the planning model's judgment.
4. **Capacity step** (Plan Session, before recap). Ask the user how Claude/Codex capacity looks
   right now and note the answer in `00-overview.md` as plan-time context. Capacity never changes a
   `driver_hint` (that derives from work nature alone); it informs the recap's routing suggestions
   and the handoff-time resolution.
5. **Kickoff line** in the story-doc template points at `agent-handoff` story-execution mode for
   every story; `loop:` tells the renderer how much planning phase to include, and `loop: direct`
   additionally allows a CLI/subagent target.
6. **"Integration Is Planned Here, Performed Elsewhere"** section names `agent-handoff` as the
   performer.

Story frontmatter delta (three new fields; all existing fields, including `flow:`, unchanged —
`flow: mechanical | design-heavy` keeps describing the work's shape, `loop:` the planning depth,
`driver_hint:` the executor affinity):

```yaml
loop: full            # full | direct — planning depth only; the lifecycle contract is identical
driver_hint: codex    # codex | claude | either — affinity from work nature only; resolved at handoff time
driver_why: one line tying the hint to the work's nature
```

## agent-handoff (new skill)

Model-invocable (no `disable-model-invocation`; no `agents/openai.yaml` guard) — mid-story sessions
must be able to invoke it, and the user can call it explicitly anytime. It renders text to paste; it
never executes the work itself. Frontmatter must be valid YAML (quote the description — the old
skill's unquoted `Triggers:` broke parsing) with `name` equal to the directory name.

**Mode selection:** an explicit mode argument wins; otherwise infer — a story doc input means
story-execution, a request naming surfaces/screenshots means visual-validation, anything else is
task mode. Say which mode and target were picked and why, in one line, before rendering.

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
state, relevant paths/symbols/anchors, constraints. Receivers only *read* the task file; never put
credentials or secrets in one.

**Target selection.** `codex-app | codex-cli | claude-cli | claude-session`, resolved as: required
capability → the user's explicit say → current availability → affinity. Anything needing rendered
screenshots must target `codex-app`; the CLI is not a silent substitute — if Codex.app capacity is
unavailable, visual validation is blocked and the skill says so.

### Mode: task (default)

Bounded work *outside the sprint ledger*, result returned to the caller — a report, a fixed config,
a research answer. No lifecycle machinery: no trailers, no merge order, no deploy gates. Never used
for a numbered sprint story.

### Mode: visual-validation (flagship)

For "implemented here, confirm it there". **Report-only by default**: the receiver drives the flows
and reports; it fixes nothing unless the task file contains an explicit mutation grant naming what
it may touch (single writer — the sending session stops editing those files until the report is
back). The task file lists changed surfaces as `(route, state)` plus what correct looks like, **and
the exact workspace identity**: repo root or worktree path, branch, HEAD SHA, whether uncommitted
changes are present, and how to launch the app (dev server command, port, account). Without that, a
fresh Codex.app session may never see the sending session's uncommitted work.

The receiving Codex.app session **ends its reply with the test scenario (steps, expected vs
observed) and inline screenshots grouped per surface — written for the user, not for another
agent.** Each shot names its driver and viewport (one line; no heavy provenance table). Codex.app
only; the skill states plainly that the CLI cannot render images.

### Mode: story-execution

Input: a planned story doc (typically from `sprint-orchestrator`). Renders the lean kickoff prompt —
all values literal, resolved at render time, no placeholders left for the executor:

```
Story 07: Report Date Presets

You are executing ONE story end-to-end.
EXECUTION MODE: STOP AT PR — DO NOT MERGE OR DEPLOY.   [or: AUTONOMOUS — merge, deploy, verify on prod.]
Read first: docs/sprints/<sprint>/07-date-presets.md, 00-overview.md, STORY-FEEDBACK.md, and repo
conventions (AGENTS.md / CLAUDE.md). If absent from this worktree, read them from trunk with
`git show origin/main:<path>` — never copy them in. Product scope and decisions there are SETTLED.
Execution contract: ~/.codex/skills/agent-handoff/EXECUTION.md — follow it exactly.
Use skills: <from the story's loop/flow — e.g. superpowers:test-driven-development>
Hard rules: every commit carries `Story: 07` and `Sprint: 2026-07-07-report-delivery-sprint`
(verbatim); never `git checkout main`; if sprint/07-* already exists on any ref the story is taken —
stop; never leave prod broken.

/goal <story goal>
```

`execution: autonomous | stop-at-pr` comes from the story doc as today and is rendered as the
EXECUTION MODE line. The contract path is spelled for the target harness (`~/.codex/skills/...` for
Codex, `~/.claude/skills/...` for Claude). `loop: full` keeps the playbook's self-directed
brainstorm/spec/plan phase; `loop: direct` tells the executor to go straight to a short TDD plan.

## EXECUTION.md (new, beside the skill)

The lifecycle contract migrated from today's `codex-execution-handoff` prompt template and prose,
addressed to the executing agent:

- Preflight: fetch; refuse an existing `sprint/NN-*` branch; `git switch -c` off `origin/main`
  (trunk default; matching `sprint-status.sh`'s `SPRINT_TRUNK` override is out of scope and noted as
  a known asymmetry); never `git checkout main`; deploy-project link check.
- Plan: per `loop:` — self-directed brainstorm/spec/plan (`full`, spec and plan artifacts live on
  the story branch) or a short TDD plan (`direct`); do the doc's "Start by verifying"; baseline +
  "before" screenshots first.
- Implement: TDD; stay inside `ownership.owns`; trailers on every commit.
- Validate locally: tests + typecheck; drive Browser Verification; "after" screenshots; open artifacts.
- Merge & deploy (AUTONOMOUS only): gate on tests + typecheck + production build + both trailers;
  overview's merge order; rebase-once-retry-once on rejected push; deploy with the project's command.
- Verify on prod (AUTONOMOUS only): drive verification on the live URL; roll back or revert if not a
  fast fix; never leave prod broken.
- `stop-at-pr` collapse: open a PR, do not merge, do not deploy; trailers still on; `DONE` flips when
  the human merges.
- Hand off: STORY-FEEDBACK.md append; "How to test this yourself" format (what changed · live URL +
  role · exact steps, expected vs observed · test data · evidence · risk + rollback · checks run ·
  open questions); tracker card: `card.done` intent (falls back to a written hand-back via
  `add_comment` where attachments are impossible).
- Evidence rules: `surfaces:` is a floor; before/after locally + after on prod per `(route, state)`;
  approved drivers only (named in the project's AGENTS.md); provenance per shot; files under
  `~/.sprint-evidence/{SPRINT}/{NN}-{SLUG}/`, never `/tmp`, never inside a worktree; screenshots
  inline in the final Codex.app message.
- Common mistakes (migrated list).
- The three legitimate early interrupts: wrong premise / genuine product ambiguity; cannot keep prod
  green; no approved driver can drive the browser verification.

## Migration (ordered — deletion is the last step, not the first)

1. Create `agent-handoff/` (SKILL.md, EXECUTION.md, README.md) and run `install.sh` — it links any
   directory containing a SKILL.md into both harnesses' skills dirs.
2. Update all references: `sprint-orchestrator/SKILL.md` + README, repo README, `test/lint-skills.sh`.
3. Delete `codex-execution-handoff/` from the repo.
4. Prune the two stale symlinks (`~/.claude/skills/codex-execution-handoff`,
   `~/.codex/skills/codex-execution-handoff`) — only if each is a symlink pointing exactly at this
   repo's deleted directory; never remove a real directory or a foreign link.
5. Known leftover: story docs in *other repos'* past sprints name the old skill in their
   planner-side kickoff line. Harmless (the line addresses the planner, not the executor); fix
   opportunistically if such a sprint is ever re-planned.

## Lint changes (`test/lint-skills.sh`)

- Orchestrator additions: `has driver_hint:`, `has loop:`, `has driver_why:`; existing checks stay.
- The codex-execution-handoff block is replaced by agent-handoff checks split across the two files:
  - `SKILL.md`: frontmatter parses as YAML and `name` equals the directory (new check class — the
    old skill's frontmatter was silently invalid); is model-invocable (`hasnt
    disable-model-invocation`); names `Codex.app` for visual-validation; report-only default and
    mutation-grant language present; workspace-identity fields named; `/goal` present; the
    story-mode template inlines an `EXECUTION MODE` line and a hard-rules line naming both trailers
    and negated `git checkout main`; `~/.handoffs` named; names both harness forms of the contract
    path (`~/.codex/skills/...` and `~/.claude/skills/...`); task mode states it is never used for a
    numbered sprint story.
  - `EXECUTION.md`: both trailers; `git checkout main` only ever negated; `git switch -c`; refuses a
    taken story; approved-driver rule; DOM-check ban; `.sprint-evidence` path; all three interrupt
    conditions; stop-at-pr collapse; `card.done` present.

## READMEs

- Repo `README.md`: skill list gains agent-handoff, drops codex-execution-handoff.
- `agent-handoff/README.md`: what it is (prompt renderer, three modes), prerequisites (Codex.app for
  anything visual), use examples.
- `sprint-orchestrator/README.md` + `SKILL.md`: pairing note points at agent-handoff.

## Non-goals

- No driver registry or model catalog; no automation of capacity detection (it is a question to the
  user).
- No changes to `sprint-status.sh`, the trailer convention, or story state derivation. (Known,
  untouched discrepancies noted during review: the prose says any `sprint/NN-*` branch reads DOING
  while the helper matches the exact slug; the helper honors `SPRINT_TRUNK` while the execution
  contract hardcodes `origin/main`.)
- No changes to the `/codex` reviewer skill.
- No portability machinery for `~/.handoffs` (configurable roots, writability probes, collision
  policy) — solo-operator setup; revisit only if a second machine or operator appears.

## Risks

- **Referenced-doc adherence.** A doc is followed less reliably than a pasted prompt. Mitigation:
  the inline hard-rules and EXECUTION MODE lines carry every catastrophic rule with literal values;
  everything else in EXECUTION.md is recoverable if skimmed.
- **Model-invocation misfire.** agent-handoff becomes invocable; a vague description could trigger
  it spuriously. Mitigation: description names concrete triggers (hand off, delegate, visual
  validation, kickoff a story) and the skill's first step is confirming there is a bounded task and
  a goal.
- **Two writers on one tree.** Visual validation with a mutation grant risks conflicting edits.
  Mitigation: report-only default; the grant names files; the sender stops editing them until the
  report returns.

## Success criteria

- `test/lint-skills.sh` and `sprint-orchestrator/test/test-sprint-status.sh` pass.
- `codex-execution-handoff` gone from repo and both skills dirs (per migration order); `agent-handoff`
  linked in both.
- A `loop: full` story and a `loop: direct` story both render story-execution prompts with literal
  trailer values and an EXECUTION MODE line; only the planning-phase instruction and allowed targets
  differ.
- The visual-validation template is report-only by default, carries workspace identity, and ends
  with inline screenshots + a test scenario addressed to the user.
