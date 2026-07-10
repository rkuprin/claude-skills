# Model-Aware Sprint Planning + Unified Agent Handoff — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make sprint planning model/harness-aware and replace `codex-execution-handoff` with a unified, anytime-callable `agent-handoff` skill (task / visual-validation / story-execution modes) backed by an `EXECUTION.md` lifecycle contract.

**Architecture:** Prose skills in `~/claude-skills`, symlinked into both `~/.claude/skills` and `~/.codex/skills`. The pasted kickoff prompt gets lean; the lifecycle contract moves to a playbook doc; catastrophic rules stay inline with literal values. TDD here means lint-first: `test/lint-skills.sh` greps the prose for invariants, so every task adds its failing lint assertions before writing the prose.

**Tech Stack:** Markdown skill files, bash (`lint-skills.sh`, `install.sh`), git.

**Spec:** `docs/superpowers/specs/2026-07-10-model-aware-sprint-planning-design.md` — authoritative for all wording decisions.

## Global Constraints

- Repo root: `~/claude-skills`. All paths below are relative to it unless `~`-prefixed.
- `/goal` ends every rendered prompt regardless of target (user decision — do not re-flag).
- `loop:` is planning depth only; every numbered sprint story keeps the full lifecycle contract.
- Visual validation is report-only by default; fixing requires an explicit mutation grant.
- Lint stays bash+grep only — no YAML-parser dependency. The "YAML validity" check class is: `name:` equals the directory name, `description:` is a quoted scalar.
- Conventional commits, imperative, ≤72 chars. Stage explicit paths only. Print `git branch --show-current` and `git status --short` alongside every commit.
- `test/lint-skills.sh` must exit 0 at every commit boundary (red is allowed only mid-task, between writing an assertion and writing the prose it checks).
- Match the existing prose voice of the repo (terse, declarative, "prose is the product").

---

### Task 1: `agent-handoff/SKILL.md` — the skill itself

**Files:**
- Modify: `test/lint-skills.sh` (append agent-handoff SKILL.md block after the existing codex-execution-handoff block; do NOT touch the old block yet)
- Create: `agent-handoff/SKILL.md`

**Interfaces:**
- Produces: `agent-handoff/SKILL.md` with the literal strings the lint asserts (listed in Step 1); Task 2 adds `EXECUTION.md` beside it; Task 4's orchestrator edits name `agent-handoff`.

- [ ] **Step 1: Add failing lint assertions**

Append to `test/lint-skills.sh`, after the last existing check and before the final `printf`/exit lines:

```bash
# --- agent-handoff (SKILL.md) ---
AH="$HERE/../agent-handoff/SKILL.md"
# Frontmatter sanity without a YAML parser: name matches the directory, and the description is a
# quoted scalar — the retired codex-execution-handoff description was unquoted, contained
# "Triggers:", and silently failed YAML parsing. Grep can prevent that class.
grep -q '^name: agent-handoff$' "$AH" 2>/dev/null && ok "handoff: name matches directory" || no "handoff: name matches directory"
grep -q '^description: "' "$AH" 2>/dev/null && ok "handoff: description is a quoted scalar" || no "handoff: description is a quoted scalar"
hasnt "handoff: model-invocable (no manual-only guard)" "disable-model-invocation" "$AH"
has   "handoff: /goal ends every prompt"     "/goal"              "$AH"
has   "handoff: names Codex.app"             "Codex.app"          "$AH"
has   "handoff: report-only default"         "Report-only by default" "$AH"
has   "handoff: mutation grant"              "mutation grant"     "$AH"
has   "handoff: workspace identity (SHA)"    "HEAD SHA"           "$AH"
has   "handoff: task files in ~/.handoffs"   "~/.handoffs"        "$AH"
has   "handoff: EXECUTION MODE inline"       "EXECUTION MODE"     "$AH"
has   "handoff: stop-at-pr rendered loud"    "STOP AT PR — DO NOT MERGE OR DEPLOY" "$AH"
has   "handoff: codex contract path"         "~/.codex/skills/agent-handoff/EXECUTION.md" "$AH"
has   "handoff: claude contract path"        "~/.claude/skills/agent-handoff/EXECUTION.md" "$AH"
has   "handoff: task mode excludes sprint stories" "numbered sprint story" "$AH"
has   "handoff: capability outranks affinity" "Capability outranks affinity" "$AH"
has   "handoff: hard rules name the story trailer"  "Story: {NN}"   "$AH"
has   "handoff: hard rules name the sprint trailer" "Sprint: {SPRINT}" "$AH"
bad=$(grep -nF 'git checkout main' "$AH" 2>/dev/null | grep -viE 'never|do not|don.t|instead of' || true)
[ -z "$bad" ] && ok "handoff: git checkout main only ever negated" || no "handoff: git checkout main appears as an instruction ($bad)"
```

Note: `has()`/`hasnt()` already tolerate a missing file (grep fails → `no`), so these fail loudly, not fatally, before the file exists.

- [ ] **Step 2: Run lint, expect the new block to fail**

Run: `test/lint-skills.sh; echo "exit=$?"`
Expected: all pre-existing checks still `ok`; every new `handoff:` check `FAIL`; `exit=1`.

- [ ] **Step 3: Write `agent-handoff/SKILL.md`**

Create with exactly this content:

````markdown
---
name: agent-handoff
description: "Render a short handoff prompt that sends bounded work to another agent — Codex.app, codex CLI, claude CLI, or a fresh Claude session. Modes: task (bounded work, report back), visual-validation (Codex.app confirms UI changes with inline screenshots), story-execution (kick off one planned sprint story end to end). Triggers: hand this off, delegate this, ask Codex to validate this visually, kick off story NN."
---

# agent-handoff — hand bounded work to another agent

One skill, three modes. It renders a prompt to paste (and usually a task file for the receiver to
read); it never executes the work itself. Before rendering, confirm there is a bounded task and an
observable goal — if either is missing, ask. Then state which mode and target you picked and why,
in one line.

## Mode and target

An explicit mode argument wins. Otherwise infer: the input is a story doc → story-execution; the
ask names surfaces or screenshots → visual-validation; anything else → task.

Targets: `codex-app` | `codex-cli` | `claude-cli` | `claude-session`. Resolve in order: required
capability → the user's explicit say → current availability (ask the user if unknown — Claude and
Codex subscriptions deplete independently) → affinity. Affinity, in two lines: Codex leans
mechanistic, devops, and browser-driving work; Claude leans creative, frontend-heavy, ambiguous
work. Capability outranks affinity: anything that must show rendered screenshots targets
`codex-app` — the CLI cannot render images and is never a silent substitute. If Codex.app capacity
is unavailable, visual work is blocked; say so instead of downgrading.

## The prompt shape (every mode)

```
<Title — becomes the receiving session's name>

Read the task file: <path>
Use skills: <skills to invoke on the other side — Claude Code and Codex share this skills repo>
<2-3 lines of live context>

/goal <observable done — almost always present>
```

`/goal` ends every prompt regardless of target. It is a command in both Codex.app and Claude Code,
and anywhere else it is plain text that still carries the goal.

## The task file

Write it to `~/.handoffs/YYYY-MM-DD-<slug>.md` (`mkdir -p ~/.handoffs`) — outside any git worktree,
which is deleted long before anyone re-reads it — unless an existing doc (story doc, spec) already
covers the task; then point at that instead. Contents: the task, current state, relevant
paths/symbols/anchors, constraints. The receiver only reads the task file. Never put credentials or
secrets in one.

## Mode: task (default)

Bounded work outside the sprint ledger; the deliverable is a result returned to the caller — a
report, a fixed config, a research answer. No lifecycle machinery: no trailers, no merge order, no
deploy gates. Never use task mode for a numbered sprint story — that is story-execution, whatever
its `loop:` value.

## Mode: visual-validation

For "implemented here, confirm it there". **Report-only by default:** the receiver drives the flows
and reports. It fixes nothing unless the task file carries an explicit mutation grant naming the
files it may touch — and then there is a single writer: the sending session stops editing those
files until the report is back.

Beyond the standard contents, the task file must carry:

- the changed surfaces as `(route, state)` pairs and what correct looks like;
- the exact workspace identity: repo root or worktree path, branch, HEAD SHA, whether uncommitted
  changes are present — without this a fresh session may never see the sender's uncommitted work;
- how to launch: dev server command, port, test account.

Target is `codex-app`, always. The receiver ends its reply with the test scenario (steps, expected
vs observed) and inline screenshots grouped per surface — written for the user, not for another
agent. Each shot names its driver and viewport; one line each, no provenance table.

Prompt template (fill everything; keep it this short):

```
Visual validation: <what changed, three words>

Read the task file: ~/.handoffs/<date>-<slug>.md
Use skills: <only if one applies; often none>
<one line: what was implemented and where it runs>
Report only — do not edit files<, except the mutation grant in the task file>.
End your reply with the test scenario (steps, expected vs observed) and inline screenshots grouped
per surface, one line of driver+viewport each. That ending is for the user, not for another agent.

/goal I can read your reply top to bottom and know, from the scenario and the inline screenshots,
whether <the change> renders and behaves correctly on every listed surface.
```

## Mode: story-execution

Input: one planned story doc (typically written by `sprint-orchestrator`; read it and its
`00-overview.md` first). Render the lean kickoff prompt below — every value literal, resolved at
render time; no placeholders left for the executor.

- `execution:` in the story doc becomes the EXECUTION MODE line: `autonomous` →
  `AUTONOMOUS — merge, deploy, verify on prod.`; `stop-at-pr` →
  `STOP AT PR — DO NOT MERGE OR DEPLOY.`
- `loop:` sets the planning-depth sentence: `full` → run the contract's self-directed
  brainstorm → spec → plan phase first; `direct` → the story is fully defined, go straight to a
  short TDD plan. `loop: direct` also allows a `codex-cli` / `claude-cli` / subagent target;
  `loop: full` stories belong in an interactive session (`codex-app` or `claude-session`).
- The contract path is spelled for the target harness:
  `~/.codex/skills/agent-handoff/EXECUTION.md` for Codex targets,
  `~/.claude/skills/agent-handoff/EXECUTION.md` for Claude targets.

```
Story {NN}: {Three Descriptive Words}

You are executing ONE story end-to-end.
EXECUTION MODE: {AUTONOMOUS — merge, deploy, verify on prod. | STOP AT PR — DO NOT MERGE OR DEPLOY.}
Read first: {STORY_DOC}, 00-overview.md, STORY-FEEDBACK.md, and repo conventions
(AGENTS.md / CLAUDE.md). If any are absent from this worktree, read them from trunk with
`git show origin/main:<path>` — never copy them in. Product scope and decisions there are SETTLED;
stop and ask only for a wrong premise or genuine product ambiguity.
Execution contract: {~/.codex|~/.claude}/skills/agent-handoff/EXECUTION.md — follow it exactly.
Planning depth: {run the contract's self-directed brainstorm → spec → plan phase first | the story
is fully defined — go straight to a short TDD plan}.
Use skills: {from the story's flow — e.g. superpowers:test-driven-development}
Hard rules: every commit carries `Story: {NN}` and `Sprint: {SPRINT}` (verbatim); never
`git checkout main`; if sprint/{NN}-* already exists on any ref the story is taken — stop; never
leave prod broken.

/goal {STORY_GOAL}
```

The first line is the story's `conversation:` value, so the receiving session names itself after
the story and its tracker card. `{SPRINT}` is the story doc's `sprint:` frontmatter value — the
sprint directory's basename, verbatim; anything else makes the story invisible to sprint status
forever.
````

- [ ] **Step 4: Run lint, expect green**

Run: `test/lint-skills.sh; echo "exit=$?"`
Expected: every check `ok` (old codex-execution-handoff block included — its files still exist); `exit=0`.

- [ ] **Step 5: Commit**

```bash
cd ~/claude-skills && git add agent-handoff/SKILL.md test/lint-skills.sh \
  && git commit -m "feat(agent-handoff): unified handoff skill, three modes" \
  && git branch --show-current && git status --short
```

---

### Task 2: `agent-handoff/EXECUTION.md` — the lifecycle contract

**Files:**
- Modify: `test/lint-skills.sh` (append the contract block after Task 1's block)
- Create: `agent-handoff/EXECUTION.md`

**Interfaces:**
- Consumes: `agent-handoff/SKILL.md` (Task 1) references this file by both harness paths.
- Produces: `agent-handoff/EXECUTION.md`; Task 6 deletes the old skill this content migrates from.

- [ ] **Step 1: Add failing lint assertions**

Append to `test/lint-skills.sh` after the Task 1 block:

```bash
# --- agent-handoff (EXECUTION.md, the lifecycle contract) ---
AHEXEC="$HERE/../agent-handoff/EXECUTION.md"
has   "contract: story trailer"              "Story: {NN}"        "$AHEXEC"
has   "contract: sprint trailer"             "Sprint:"            "$AHEXEC"
has   "contract: worktree-safe branching"    "git switch -c"      "$AHEXEC"
has   "contract: refuses a taken story"      "already exists"     "$AHEXEC"
has   "contract: approved drivers"           "approved driver"    "$AHEXEC"
has   "contract: bans DOM substitution"      "DOM"                "$AHEXEC"
has   "contract: evidence outside the repo"  ".sprint-evidence"   "$AHEXEC"
has   "contract: stop-at-pr collapse"        "do not merge, do not deploy" "$AHEXEC"
has   "contract: tracker done intent"        "card.done"          "$AHEXEC"
has   "contract: third interrupt condition"  "approved driver can drive" "$AHEXEC"
hasnt "contract: no per-sprint HANDOFF.md"   "HANDOFF.md"         "$AHEXEC"
hasnt "contract: no CLAIMED rename"          ".CLAIMED.md"        "$AHEXEC"
bad=$(grep -nF 'git checkout main' "$AHEXEC" 2>/dev/null | grep -viE 'never|do not|don.t|instead of' || true)
[ -z "$bad" ] && ok "contract: git checkout main only ever negated" || no "contract: git checkout main appears as an instruction ($bad)"
```

- [ ] **Step 2: Run lint, expect only the new `contract:` checks to fail**

Run: `test/lint-skills.sh; echo "exit=$?"`
Expected: `contract:` checks `FAIL` (except the two `hasnt` and the negation check, which pass vacuously on a missing file); everything else `ok`; `exit=1`.

- [ ] **Step 3: Write `agent-handoff/EXECUTION.md`**

Create with exactly this content:

````markdown
# Execution contract — one sprint story, end to end

You are executing ONE planned story. Your kickoff prompt names the story doc, the sprint, your
EXECUTION MODE, and your `/goal`. This contract is the how. Product scope and decisions in the
story doc and `00-overview.md` are SETTLED; if you find a wrong premise, an internal contradiction,
or a genuine product ambiguity, STOP and ask.

## 0. Preflight

- `git fetch origin`
- If `sprint/{NN}-*` already exists on any ref, the story is taken. STOP and report; never co-opt
  someone else's branch.
- `git switch -c sprint/{NN}-{SLUG} origin/main` — NEVER run `git checkout main`: trunk is checked
  out in another worktree and the command fails. Trunk is `origin/main`; if the project uses
  another trunk, `00-overview.md` says so. (`sprint-status.sh` honors `SPRINT_TRUNK`; that
  asymmetry is known and not yours to fix.)
- Confirm this worktree is linked to the real deploy project before any deploy (see AGENTS.md).

## 1. Plan

- Planning depth comes from your kickoff prompt: either run a self-directed brainstorm → spec →
  plan phase (weigh 2-3 approaches; keep the spec and plan as files on the story branch), or go
  straight to a short TDD plan. Self-directed means your own loop under your single late `/goal`
  checkpoint — not a user-gated workflow.
- Do the story doc's "Start by verifying" first. Reproduce the bug / establish the baseline BEFORE
  changing anything, capturing the "before" screenshots while you are there. Restate In/Out of
  scope.

## 2. Implement

- TDD: failing test first.
- Stay strictly inside `ownership.owns`; never touch `do_not_touch`.
- Every commit you make for this story carries the trailer block from your kickoff prompt:

      Story: {NN}
      Sprint: {SPRINT}

  This is the only record that the story landed. A commit without both is invisible to sprint
  status.

## 3. Validate locally

Tests + typecheck; drive the story doc's Browser Verification locally; capture the "after"
screenshots; open any produced artifact. Fix until green.

## 4. Merge & deploy — AUTONOMOUS mode only

Under STOP AT PR: open a PR, do not merge, do not deploy. Trailers still go on every commit; `DONE`
flips when the human merges. Skip to step 6.

- Gate: story tests + typecheck + a production build all pass, and the story's commits carry BOTH
  trailers.
- Merge into trunk in `00-overview.md`'s merge order; ensure trunk is green.
- If the push is rejected because another session landed first: `git pull --rebase` and retry ONCE.
  Rejected again → STOP and report. Never force-push.
- Deploy with the project's deploy command (AGENTS.md).

## 5. Verify on prod — AUTONOMOUS mode only

- Drive the Browser Verification against the LIVE URL with a real test account; capture prod
  screenshots.
- Defect → fix, re-gate, redeploy, re-check. If prod breaks and it is not a fast fix → roll back
  (or revert the merge) and report. Never leave prod broken.

## 6. Hand off

- Append findings to STORY-FEEDBACK.md, including any surface you had to add to `surfaces:`.
- Produce the "How to test this yourself" section: what changed · live URL + role/account · exact
  steps, expected vs observed · test data/accounts · evidence (inline screenshots + provenance) ·
  risk + how to roll back · checks run (commands + results, build, deploy id) · open questions.
- Tracker: fire the `card.done` intent per the project's tracker binding. Where attachments are
  impossible (e.g. the Asana V2 MCP), the written hand-back reaches the card via `add_comment`.
- State branch, files, tests + results, deploy id.

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

1. a wrong premise or genuine product ambiguity;
2. an inability to keep prod green (roll back and report);
3. no approved driver can drive the browser verification.

## Common mistakes

- Never run `git checkout main` — trunk lives in another worktree; use
  `git switch -c <branch> origin/main`.
- Commits without both trailers — the story ships and sprint status calls it TODO forever.
- Co-opting an existing `sprint/NN-*` branch instead of stopping.
- Force-pushing after a rejected push. Rebase once, retry once, then stop.
- Deploying from a feature branch instead of merging to trunk first — "live" then ≠ what you
  tested.
- Silently swapping browser drivers — legal only if AGENTS.md approves the driver and the hand-back
  declares it.
- Writing evidence to `/tmp` or into the worktree — both vanish before review.
- Progress pings mid-run — defeats the single-checkpoint purpose.
````

- [ ] **Step 4: Run lint, expect green**

Run: `test/lint-skills.sh; echo "exit=$?"`
Expected: all checks `ok`; `exit=0`.

- [ ] **Step 5: Commit**

```bash
cd ~/claude-skills && git add agent-handoff/EXECUTION.md test/lint-skills.sh \
  && git commit -m "feat(agent-handoff): EXECUTION.md lifecycle contract" \
  && git branch --show-current && git status --short
```

---

### Task 3: `agent-handoff/README.md` + install into both harnesses

**Files:**
- Create: `agent-handoff/README.md`
- No repo change from installing: symlinks live outside the repo.

**Interfaces:**
- Consumes: Tasks 1-2 files.
- Produces: `~/.claude/skills/agent-handoff` and `~/.codex/skills/agent-handoff` symlinks that the rendered prompts' contract paths depend on.

- [ ] **Step 1: Write `agent-handoff/README.md`**

````markdown
# agent-handoff

Renders a short prompt that hands bounded work to another agent — Codex.app, the codex CLI, the
claude CLI, or a fresh Claude session. One skill, three modes:

| Mode | For | Ends with |
|---|---|---|
| `task` (default) | bounded work outside the sprint ledger | a result returned to the caller |
| `visual-validation` | "implemented here, confirm it there" | test scenario + inline screenshots, for the human |
| `story-execution` | one planned sprint story, end to end | the story's late `/goal` checkpoint |

It is a prompt renderer: it produces a task file (default `~/.handoffs/`) plus text you paste. It
never executes the work itself. Every prompt ends with `/goal` — a command in both Codex.app and
Claude Code, plain text anywhere else.

The story lifecycle contract (branching, trailers, gates, evidence, rollback) lives in
[`EXECUTION.md`](EXECUTION.md), which rendered story prompts reference by the receiving harness's
path. The prompt itself keeps only the catastrophic rules inline, with literal values.

## Prerequisites

- **Anything visual targets Codex.app** — only the app renders screenshots inline; the CLI is never
  a silent substitute.
- Story-execution assumes the consuming project's AGENTS.md / CLAUDE.md supply the deploy command,
  live URL, gate commands, test accounts, and approved visual drivers — nothing is restated here.
- Installed in **both** harnesses (`./install.sh` and `CLAUDE_SKILLS_DIR=~/.codex/skills
  ./install.sh`) so the contract path resolves wherever the prompt lands.

## Use it

```
/agent-handoff                       # Claude — infers mode from what you hand it
$agent-handoff                       # Codex
/agent-handoff docs/sprints/<sprint>/07-date-presets.md   # story-execution
```

Companion to [`sprint-orchestrator`](../sprint-orchestrator/), which writes the story docs that
story-execution mode consumes — but nothing here requires a sprint: the skill is callable anytime.
````

- [ ] **Step 2: Install into both harnesses**

```bash
cd ~/claude-skills && ./install.sh && CLAUDE_SKILLS_DIR=~/.codex/skills ./install.sh
```

Expected: both runs print `linked  agent-handoff  ->  ...` among the links.

- [ ] **Step 3: Verify the symlinks resolve**

```bash
readlink ~/.claude/skills/agent-handoff && readlink ~/.codex/skills/agent-handoff \
  && test -f ~/.claude/skills/agent-handoff/EXECUTION.md \
  && test -f ~/.codex/skills/agent-handoff/EXECUTION.md && echo BOTH-OK
```

Expected: two paths ending in `/claude-skills/agent-handoff`, then `BOTH-OK`.

- [ ] **Step 4: Commit**

```bash
cd ~/claude-skills && git add agent-handoff/README.md \
  && git commit -m "docs(agent-handoff): README — modes, prerequisites, install" \
  && git branch --show-current && git status --short
```

---

### Task 4: sprint-orchestrator — model gate, planning depth, drivers, capacity

**Files:**
- Modify: `test/lint-skills.sh` (orchestrator additions, appended inside the orchestrator section after the `wave promoted` line)
- Modify: `sprint-orchestrator/SKILL.md`

**Interfaces:**
- Consumes: `agent-handoff` (named in the kickoff line and integration section).
- Produces: story frontmatter fields `loop:`, `driver_hint:`, `driver_why:` that agent-handoff's story-execution mode reads.

- [ ] **Step 1: Add failing lint assertions**

In `test/lint-skills.sh`, directly after the line `has   "orchestrator: wave promoted"         "wave:"              "$ORCH"`, insert:

```bash
has   "orchestrator: loop field"            "loop:"              "$ORCH"
has   "orchestrator: driver_hint field"     "driver_hint:"       "$ORCH"
has   "orchestrator: driver_why field"      "driver_why:"        "$ORCH"
has   "orchestrator: capability outranks affinity" "Capability outranks affinity" "$ORCH"
has   "orchestrator: strongest-model gate"  "Strongest Model"    "$ORCH"
```

- [ ] **Step 2: Run lint, expect exactly those five to fail**

Run: `test/lint-skills.sh; echo "exit=$?"`
Expected: five new `FAIL` lines, all else `ok`; `exit=1`.

- [ ] **Step 3: Edit `sprint-orchestrator/SKILL.md`** — six surgical edits.

**(a)** After the intro paragraph (`Manual sprint-planning skill ... declare work done.`) and before `## Contract`, insert:

```markdown
## Run This on the Strongest Model

Sprint planning gets the most capable model available. First, name the model you are running as.
If it is not the strongest tier reachable right now (today: Fable, else Opus, on Claude Code; Sol
at ultra effort on Codex), say so and offer to stop so the user can relaunch. No hard block — but
proceeding on a lesser model needs the user's explicit go-ahead, recorded in `00-overview.md`.
```

**(b)** Replace the `## Plan Session` list:

Old:
```markdown
## Plan Session

1. Collect raw sprint inputs without filtering.
2. Verify every candidate against current source truth. If a premise is stale, already shipped, impossible, or out of scope, cut or reframe it and record why.
3. Split surviving work into stories by blast radius, file ownership, and dependency order. Prefer serial stories for shared hotspots over optimistic parallelism.
4. Write `00-overview.md`, `STORY-FEEDBACK.md`, and one story doc per survivor.
5. Recap open stories with kickoff prompts and any unresolved product questions.
```

New:
```markdown
## Plan Session

This is high-level planning backed by in-depth research — never per-story implementation planning.
`loop: full` (default): the story's execution session runs its own self-directed brainstorm → spec
→ plan → execute phases under its single late `/goal` checkpoint. `loop: direct`: the story is
simple enough to define fully here; the executor goes straight to a short TDD plan, and the story
may be delegated to a cheaper transport (subagent, `codex exec`, `claude -p`). Either way the
lifecycle contract is identical — `loop:` never waives trailers, branch discipline, or gates.

1. Collect raw sprint inputs without filtering.
2. Verify every candidate against current source truth. If a premise is stale, already shipped, impossible, or out of scope, cut or reframe it and record why.
3. Split surviving work into stories by blast radius, file ownership, and dependency order. Prefer serial stories for shared hotspots over optimistic parallelism.
4. Write `00-overview.md`, `STORY-FEEDBACK.md`, and one story doc per survivor.
5. Ask the user how Claude/Codex capacity looks right now; note the answer in `00-overview.md` as plan-time context. Capacity never changes a `driver_hint` — it informs the recap's routing suggestions and the handoff-time resolution.
6. Recap open stories with kickoff prompts and any unresolved product questions.
```

**(c)** Before `## Story Doc Shape`, insert:

```markdown
## Drivers

Codex leans mechanistic, devops, and browser-driving work; Claude leans creative, frontend-heavy,
ambiguous work. Frontend visual validation renders only in Codex.app. Capability outranks affinity
— a frontend story implemented on Claude still ends with a visual-validation handoff to Codex.app;
affinity routes stages, not just whole stories. Beyond these lines, use judgment.

`driver_hint:` derives from the work's nature ONLY — never from today's capacity. The driver is
resolved at handoff time: required capability → the user's explicit say → current availability →
affinity.
```

**(d)** In the story-doc frontmatter template, after the line `flow: mechanical             # mechanical | design-heavy`, add:

```yaml
loop: full                   # full | direct — planning depth only; the lifecycle contract is identical
driver_hint: codex           # codex | claude | either — affinity from work nature only; resolved at handoff time
driver_why: <one line tying the hint to the work's nature>
```

**(e)** Kickoff line — replace:

Old: `` `codex-execution-handoff` for `07-<slug>.md`, then hand the rendered prompt to the executor. ``
New: `` `agent-handoff` (story-execution mode) for `07-<slug>.md`, then hand the rendered prompt to the executor. ``

**(f)** Integration section — replace:

Old: `` card belong to `codex-execution-handoff`. Do not restate the lifecycle here. ``
New: `` card belong to `agent-handoff`'s execution contract (`EXECUTION.md`). Do not restate the lifecycle here. ``

- [ ] **Step 4: Run lint, expect green**

Run: `test/lint-skills.sh; echo "exit=$?"`
Expected: all `ok`; `exit=0`. (The old codex-execution-handoff block still passes — its files still exist.)

- [ ] **Step 5: Commit**

```bash
cd ~/claude-skills && git add sprint-orchestrator/SKILL.md test/lint-skills.sh \
  && git commit -m "feat(sprint-orchestrator): model gate, loop depth, driver hints" \
  && git branch --show-current && git status --short
```

---

### Task 5: point the READMEs at agent-handoff

**Files:**
- Modify: `README.md` (repo root)
- Modify: `sprint-orchestrator/README.md`

**Interfaces:**
- Consumes: `agent-handoff/` (Task 1-3).

- [ ] **Step 1: Edit repo `README.md`**

Replace the table row:

Old: `| [`codex-execution-handoff`](codex-execution-handoff/) | Renders the kickoff prompt that runs one story end to end |`
New: `| [`agent-handoff`](agent-handoff/) | Hands bounded work to another agent — task, visual-validation, and story-execution modes |`

The following line (`The last two are companions: one plans, the other hands off.`) stays — still true.

- [ ] **Step 2: Edit `sprint-orchestrator/README.md`**

Replace:

Old:
```markdown
Pairs with [`codex-execution-handoff`](../codex-execution-handoff/), which renders the kickoff
prompt that actually runs a story.
```

New:
```markdown
Pairs with [`agent-handoff`](../agent-handoff/), whose story-execution mode renders the kickoff
prompt that actually runs a story.
```

- [ ] **Step 3: Verify no stale references outside the retiring skill and docs/**

Run: `cd ~/claude-skills && grep -rn 'codex-execution-handoff' --include='*.md' --include='*.sh' . | grep -v docs/superpowers | grep -v '^\./codex-execution-handoff/' | grep -v '.git/'`
Expected: only `test/lint-skills.sh` hits (its old block — removed in Task 6).

- [ ] **Step 4: Commit**

```bash
cd ~/claude-skills && git add README.md sprint-orchestrator/README.md \
  && git commit -m "docs(repo): point READMEs at agent-handoff" \
  && git branch --show-current && git status --short
```

---

### Task 6: retire codex-execution-handoff

**Files:**
- Modify: `test/lint-skills.sh` (delete the old `--- codex-execution-handoff ---` block: the `HAND=` line and every check referencing `$HAND`)
- Delete: `codex-execution-handoff/` (SKILL.md, README.md)
- Outside repo: prune two symlinks, guarded.

**Interfaces:**
- Consumes: Tasks 1-5 complete (replacement installed and referenced everywhere first — the migration order is the point).

- [ ] **Step 1: Remove the old lint block**

In `test/lint-skills.sh`, delete the contiguous block starting at the comment `# --- codex-execution-handoff ---` through the last `$HAND` check (`has "handoff: third interrupt condition" "approved driver can drive" "$HAND"`). Do not touch the agent-handoff blocks added in Tasks 1-2.

- [ ] **Step 2: Delete the skill directory**

```bash
cd ~/claude-skills && git rm -r codex-execution-handoff
```

- [ ] **Step 3: Prune the stale symlinks — guarded: only a symlink pointing exactly at the deleted directory**

```bash
for d in ~/.claude/skills ~/.codex/skills; do
  L="$d/codex-execution-handoff"
  if [ -L "$L" ] && [ "$(readlink "$L")" = "$HOME/claude-skills/codex-execution-handoff" ]; then
    rm "$L" && echo "pruned $L"
  else
    echo "left alone: $L"
  fi
done
```

Expected: `pruned` twice. `left alone` for anything unexpected — investigate before forcing.

- [ ] **Step 4: Run lint, expect green with no old-skill checks**

Run: `test/lint-skills.sh; echo "exit=$?"`
Expected: all `ok`, no line mentioning a `$HAND` check; `exit=0`.

- [ ] **Step 5: Commit**

```bash
cd ~/claude-skills && git add test/lint-skills.sh \
  && git commit -m "chore(repo): retire codex-execution-handoff into agent-handoff" \
  && git branch --show-current && git status --short
```

(`git rm` already staged the deletions.)

---

### Task 7: full verification sweep

**Files:** none modified.

- [ ] **Step 1: All test suites**

```bash
cd ~/claude-skills && test/lint-skills.sh && sprint-orchestrator/test/test-sprint-status.sh && codex/test/test.sh
```

Expected: lint all `ok` / exit 0; `18` assertions pass; `29 passed, 0 failed`.

- [ ] **Step 2: Success-criteria spot checks (from the spec)**

```bash
ls ~/.claude/skills/agent-handoff ~/.codex/skills/agent-handoff \
  && ! test -e ~/claude-skills/codex-execution-handoff \
  && ! test -e ~/.claude/skills/codex-execution-handoff \
  && ! test -e ~/.codex/skills/codex-execution-handoff && echo MIGRATION-OK
grep -c 'EXECUTION MODE' agent-handoff/SKILL.md   # ≥ 1
grep -c 'Report-only by default' agent-handoff/SKILL.md   # ≥ 1
```

Expected: `MIGRATION-OK`; both grep counts ≥ 1.

- [ ] **Step 3: Confirm clean tree**

Run: `git -C ~/claude-skills status --short` — expected: empty.
