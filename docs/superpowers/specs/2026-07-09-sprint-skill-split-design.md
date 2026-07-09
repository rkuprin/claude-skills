# Sprint planning / Codex handoff — skill boundary, state model, evidence protocol

**Date:** 2026-07-09
**Skills:** `sprint-orchestrator`, `codex-execution-handoff`
**Status:** design, approved for planning

## Problem

The premise "sprint-orchestrator is one heavy skill, split it" is false. The split already happened
on 2026-07-08: `~/.claude/skills/sprint-orchestrator/SKILL.md` (152 lines) and
`~/.claude/skills/codex-execution-handoff/SKILL.md` (91 lines). Neither is tracked in git.

The weight is not in the skill files. It is in what they force you to write per sprint, and in the
seams the split left unfinished. Six defects, all verified against `~/lead-us`:

1. **The two skills contradict each other.** The orchestrator's story template ends with
   `On finish: stop at PR/merge decision, do not merge`. `codex-execution-handoff` prescribes
   merge → deploy → verify-on-prod and states it "deliberately overrides that". The story doc and
   the kickoff prompt hand the executing agent opposite instructions. In `lead-us` this was
   resolved by hand-rewriting every story's Handoff section.

2. **Planning cannot call handoff.** `sprint-orchestrator` sets `disable-model-invocation: true`,
   so no model can invoke it — yet `codex-execution-handoff` says
   "**REQUIRED BACKGROUND:** invoke `sprint-orchestrator`". That instruction is unfulfillable.
   The reverse direction (planning → handoff) does not exist in either file.

3. **The lifecycle is written three times per sprint.** Once generically in
   `codex-execution-handoff/SKILL.md`; again in a hand-authored ~100-line
   `docs/sprints/<sprint>/HANDOFF.md`; again inside every story doc's `## Goal` section. They drift.

4. **Story state on trunk is inverted.** The claim rename is bundled into the story's own feature
   commit on the story's own branch — e.g. `8c72724 feat(reports): add date range presets` contains
   `rename 07-date-presets.md => 07-date-presets.CLAIMED.md`. It therefore reaches trunk only when
   the story merges. On `origin/main` today, ten docs read `.CLAIMED.md` — among them stories
   `STORY-FEEDBACK.md` records as merged, deployed and prod-verified (07, 08, 11) and stories
   `00-overview.md` marks shipped (01, 04) — while `10-alerts-analyzer.md` reads TODO with
   `sprint/10-alerts-analyzer` checked out in a live worktree. `Find Open Stories` reports
   finished work as in-progress and
   offers up the one story actively being worked on. The 2026-07-02 sprint did it correctly
   (`aa39fdf chore(sprint): claim Story 07 quick-wins` is standalone); the autonomous flow dropped
   that step.

5. **`done/` has never been used.** The skill says a story is complete only once a human moves its
   doc into `done/`. That has happened zero times across 18 stories in two sprints. `done/` does not
   exist on `origin/main`.

6. **Screenshot evidence rots.** The instruction exists ("capture before/after screenshots for
   anything visual") and Codex obeyed it — writing to `/tmp/strix-*.png`. Every Evidence line in
   `STORY-FEEDBACK.md` points outside the repo at files one reboot from deletion. Nothing specifies
   which surfaces, which states, or where the files go.

Two smaller ones: the template has drifted from real usage (real docs carry `wave:`, `owns_hunk:`,
`shared_note:`, and a `## Browser Verification` section that the template never mentions but that
`codex-execution-handoff` depends on — 10 of 10 stories have one); and `Find Open Stories` globs
`[0-9][0-9]-*.md`, which fails on `06b-target-header-scale.md`, making that story invisible.

## Decisions

| # | Decision |
|---|----------|
| 1 | Merge authority is per-sprint: `execution: autonomous \| stop-at-pr` |
| 2 | No binding file. Project facts come from the project's `AGENTS.md` / `CLAUDE.md` |
| 3 | The planner generates a conversation title; the handoff transports it |
| 4 | Screenshots are surfaced inline in Codex.app's final message; Asana attachment is impossible |
| 5 | State is two moves on trunk: `.md` → `.CLAIMED.md` → `done/`. Under `autonomous` Codex makes both; under `stop-at-pr` Codex claims and the human moves to `done/` |
| 6 | Codex claims on trunk as step 0, before cutting the story branch |
| 7 | Both skills move into `~/claude-skills`, symlinked into Claude and Codex |

## Design

### 1. Skill boundary

**`sprint-orchestrator` — planning.** Keeps: the verification contract, filesystem state, plan
session, story-doc template, tracker binding (`card.create`), `Find Open Stories`, planning
guardrails. It loses `Claim And Run` entirely, and loses the mechanical half of `Integrate`.

`Integrate` does not split cleanly, so state where each half goes. Planning keeps the parts that are
planning outputs: **merge order and shared-file hotspots are decided at plan time and recorded in
`00-overview.md`**, and **sweeping `STORY-FEEDBACK.md` for follow-up stories** is a plan-session
activity. Execution takes the mechanical parts: performing the merge in that order, resolving the
named hotspots, deploying, moving the doc to `done/`, and `card.done`.

**`codex-execution-handoff` — execution.** Owns: the lifecycle, the `/goal` late-checkpoint, the
deploy gate and rollback, the claim/done filesystem transitions, `card.done`, the screenshot
protocol, and the hand-back format — in both `execution:` modes. Under `stop-at-pr` it describes the
human-gated variant rather than deferring to a section in the orchestrator, so integration is
documented in exactly one place.

The per-sprint `HANDOFF.md` is deleted. The lifecycle exists once, in the skill. Project facts are
never restated: `lead-us/AGENTS.md` already carries `vercel --prod --yes`, `npx tsc --noEmit`,
`app.strixrise.com`, and a pointer to `TEST_ACCOUNTS.md`, and Codex inherits it per project.

When a plan session finishes and `execution: autonomous`, `sprint-orchestrator` invokes
`codex-execution-handoff` to render kickoff prompts for the stories whose `depends_on` are
satisfied. `codex-execution-handoff` remains independently invocable per story afterward.

Two corrections fall out. `codex-execution-handoff`'s unfulfillable "invoke `sprint-orchestrator`"
becomes "read the story doc and `00-overview.md`". The orchestrator's `do not merge` line becomes
conditional on `execution:`, ending the contradiction.

This does not shrink `sprint-orchestrator` much: it sheds roughly 25 lines and gains roughly 15.
The saving is per-sprint — one 100-line `HANDOFF.md` and sixteen restatements of the lifecycle.

### 2. Story doc contract

Frontmatter is the interface between the two skills. New and promoted fields marked:

```yaml
story: 06
title: 3-target report header
conversation: "Story 06: Monthly Target Header"   # NEW
sprint: 2026-07-07-report-delivery-sprint
execution: autonomous            # NEW — copied from 00-overview.md
flow: mechanical                 # mechanical | design-heavy
branch: sprint/06-target-header
depends_on: [05]
wave: 2                          # PROMOTED — in real docs, absent from template
frontend: true                   # NEW — drives the screenshot requirement
surfaces:                        # NEW — required iff frontend: true
  - route: /reports
    states: [targets set, targets unset]
ownership:
  owns: [src/components/reports/report-header-strip.tsx]
  owns_hunk: [...]               # PROMOTED
  do_not_touch: [...]
  shared_note: ...               # PROMOTED
tracker_card:
```

`mode: shaped | open` is dropped. It is unused, and real docs repurposed it to `mode: claimed`,
which the filename already encodes.

`## Browser Verification` joins the template. Every real story has one and the handoff depends on it.

Each story's `## Goal` section shrinks to the `/goal` line alone. No lifecycle restatement.

`execution:` is declared once in `00-overview.md` and **copied into every story's frontmatter**. The
story doc is a prompt for a fresh agent; it must not require reading the overview to know whether it
may merge.

`conversation:` is `Story NN: <Three Descriptive Words>`, generated by the planner. It matches the
Asana card title convention already recorded in `lead-us/.claude/skills/asana/SKILL.md`
(`Story NN: <title>`), so card and session titles align without extra work.

### 3. Claim and state protocol

State is the doc path, and both moves happen **on trunk**, performed by Codex:

```
docs/sprints/<sprint>/NN-<slug>.md          TODO
docs/sprints/<sprint>/NN-<slug>.CLAIMED.md  DOING
docs/sprints/<sprint>/done/NN-<slug>.md     DONE
```

**Claim is step 0 of the kickoff prompt, before the story branch exists:**

```bash
git checkout main && git pull
git mv docs/sprints/<sprint>/NN-<slug>.md docs/sprints/<sprint>/NN-<slug>.CLAIMED.md
git commit -m "chore(sprint): claim story NN"
git push
git checkout -b sprint/NN-<slug>
```

Codex never renames the doc again. The rename disappears from the feature diff, and no two places
compete to rename the same path.

**Done is the last step, also on trunk,** after the merge and a green prod verification:
`git mv NN-<slug>.CLAIMED.md done/NN-<slug>.md`, committed and pushed.

"Done" now means *Codex merged, deployed, and verified it* — not *Rodion confirmed it*. This is a
deliberate semantic change. Post-handoff review findings go to `STORY-FEEDBACK.md` or become a new
story. A doc in `done/` is never reopened. Concretely: Story 11's "Rodion review refactor" and
Story 08's date-picker rework would have been new stories.

`Find Open Stories` keeps not scanning `done/`. Its glob widens from `[0-9][0-9]-*.md` to
`[0-9][0-9]*-*.md` so suffixed stories like `06b-target-header-scale.md` are visible.

Under `execution: stop-at-pr`, Codex performs the claim and stops at the PR; the human merges and
performs the `done/` move.

### 4. Screenshot and evidence protocol

The planner sets `frontend: true` and enumerates `surfaces:`. The trigger is **not** "does
`ownership.owns` include `src/components/**`" — Story 05 was `lib/` date math that changed what the
report header rendered. The rule is: *does any user-visible surface change?* When unsure, set
`frontend: true` and name the surface.

`codex-execution-handoff` expands `surfaces:` into a required matrix. For each `(route, state)`:

- **before** and **after**, captured locally;
- **after**, captured on the live URL.

The before-shot anchors the lifecycle step that already demands "establish the baseline BEFORE
changing anything" but today produces no artifact.

Files land in `docs/sprints/<sprint>/evidence/NN-<slug>/`, gitignored via
`docs/sprints/**/evidence/`. Not `/tmp`. Relative links in `STORY-FEEDBACK.md` then resolve during
the review window instead of dying on reboot.

**`codex-execution-handoff` targets Codex.app, not the Codex CLI.** Codex.app renders images, so the
hand-back embeds the screenshots inline in its final message, grouped before/after per surface. That
is the confirmation step. The skill states this platform assumption explicitly.

Attaching to the Asana card is not possible and the skill must not suggest it. The Asana V2 MCP's
write tools are `create_tasks`, `create_project`, `update_tasks`, `delete_task`, `add_comment`, and
`create_project_status_update` — there is no attachment-upload tool. Asana's documentation states
that MCP tokens are valid only for the MCP server and do not work with the REST API, closing the
`/attachments` fallback. The written hand-back still reaches the card via `add_comment`.

With `frontend: false`, no screenshots are required — but a produced artifact (PDF, email, export)
must still be opened and confirmed, as today.

### 5. Kickoff prompt

Rendered by `codex-execution-handoff` from the story doc. Shape:

1. First line: the `conversation:` title, so the Codex.app session is named for the story.
2. Step 0: claim on trunk, then branch (§3).
3. Steps 1–6: plan → implement → validate locally → merge & deploy → verify on prod → hand off.
   Under `execution: stop-at-pr`, steps 4–5 collapse to "open a PR, do not merge".
4. Reading list: the story doc, `00-overview.md`, `STORY-FEEDBACK.md`, `AGENTS.md` / `CLAUDE.md`.
5. Closing `/goal` line, verbatim from the story doc.

The prompt does not restate the plan, the deploy command, or the live URL. Those live in the story
doc and `AGENTS.md`.

### 6. Packaging

Both skills move into `~/claude-skills/`, joining `codex`. `install.sh` links them into
`~/.claude/skills`; `CLAUDE_SKILLS_DIR=~/.codex/skills ./install.sh` links them into Codex's skills
directory. The override already exists — no script change. One file, two agents, drift impossible.

The two drifted frontmatters reconcile into one. The description is worded to cover both invocation
sigils (`/sprint-orchestrator` and `$sprint-orchestrator`). Codex's tolerance of the Claude-specific
`disable-model-invocation: true` key must be verified before the symlink is created; if Codex errors
on unknown keys, the skills stay separately installed and this decision reverts.

## Non-goals

- Rewriting the tracker binding. `card.create` / `card.done` stay as they are.
- Adding a real claim lock. `.CLAIMED.md` remains a convention; the step-0 move narrows the race to
  seconds, which is sufficient for a single operator launching sessions one at a time.
- Changing the story-doc prose sections beyond adding `## Browser Verification` and shrinking `## Goal`.

## One-time migration

These touch `~/lead-us` and need an explicit go-ahead per item:

1. Eighteen docs sit at `.CLAIMED.md` across the two sprints and none have moved to `done/`. Backfill
   requires a per-story decision about what actually shipped.
2. `2026-07-02-functional-sprint/00-sprint-overview.md` vs `2026-07-07-report-delivery-sprint/00-overview.md`.
   The skill names `00-overview.md`; rename the older one or leave it.
3. Delete `docs/sprints/2026-07-07-report-delivery-sprint/HANDOFF.md` once the skill supersedes it.
4. Add `docs/sprints/**/evidence/` to `.gitignore`.
5. Record in `lead-us/AGENTS.md` under Gotchas: the in-app browser connector times out on auth-gated
   flows; use Playwright Core with system Chrome. Stories 07, 08, and 11 each rediscovered this
   independently. It is a project fact, not a skill fact.

Separately, the stale copies at `~/Downloads/sprint-orchestrator-skill/` and
`~/Documents/Codex/2026-07-07/files-mentioned-by-the-user-name/outputs/sprint-orchestrator/` should be
deleted once `~/claude-skills` is the source of truth.

## Risks

- **Dual-installing `codex-execution-handoff` puts an authoring skill in the executor's skill list**,
  where Codex could auto-invoke it mid-story. Harm is low — it would re-read its own lifecycle — but
  `install.sh` links every directory containing a `SKILL.md` and offers no exclusion.
- **A claim commit races another session's push to trunk.** Both are docs-only; `git pull --rebase`
  before push resolves it. Same exposure the existing merge flow already has.
- **`done/` meaning "Codex verified" loses the "Rodion confirmed" signal.** Accepted: that signal now
  lives in the review that produces follow-up stories, not in a filesystem state nobody maintained.

## Success criteria

1. On trunk, for every story: `.md` ⇔ nobody is working on it; `.CLAIMED.md` ⇔ a session is live;
   `done/` ⇔ merged, deployed, verified. `Find Open Stories` output matches reality.
2. A sprint produces no `HANDOFF.md`, and no story doc restates the lifecycle.
3. A frontend story's hand-back shows before/after screenshots inline for every declared
   `(route, state)`, and its evidence links resolve from the repo.
4. `sprint-orchestrator` and `codex-execution-handoff` each exist as exactly one file on disk,
   reachable from both `~/.claude/skills` and `~/.codex/skills`.
5. No story doc contains both "do not merge" and a merge-and-deploy `/goal`.
