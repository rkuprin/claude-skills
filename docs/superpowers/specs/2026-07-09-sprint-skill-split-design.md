# Sprint planning / Codex handoff — skill boundary, state model, evidence protocol

**Date:** 2026-07-09
**Skills:** `sprint-orchestrator`, `codex-execution-handoff`
**Status:** design, approved for planning (revision 2, after independent Codex review)

## Revision history

Revision 1 was reviewed by Codex and partially falsified. Three things changed:

- **Claim-on-trunk as executor step 0 was removed.** It cannot work: Codex.app runs stories in linked
  git worktrees, and `main` is checked out in `~/.codex/worktrees/221e/lead-us`. Git refuses to check
  out a branch already live in another worktree, so `git checkout main` fails from every Codex session.
- **The hard browser gate was softened to an approved-driver rule.** Revision 1 claimed three stories
  hit the browser-connector timeout. The real count is eight — 01, 04, 06, 07, 08, 11, 12, 13 — i.e.
  effectively every frontend story. A gate that halts all of them is not a gate, it is a stop.
- **Filesystem state was replaced with derived state.** See §3. Both `.CLAIMED.md` and `done/` are gone.

Codex also corrected an overclaim: revision 1 said the 2026-07-02 sprint "did it correctly."
It did not. `aa39fdf` is a standalone claim commit, but `fd45156 feat(feedback)` renames three story
docs inside a feature commit. One good example is not a followed convention.

## Problem

The premise "sprint-orchestrator is one heavy skill, split it" is false. The split already happened
on 2026-07-08: `~/.claude/skills/sprint-orchestrator/SKILL.md` (152 lines) and
`~/.claude/skills/codex-execution-handoff/SKILL.md` (91 lines). Neither is tracked in git.

The weight is not in the skill files. It is in what they force you to write per sprint, and in the
seams the split left unfinished. Verified against `~/lead-us`:

1. **The two skills contradict each other.** The orchestrator's story template ends with
   `On finish: stop at PR/merge decision, do not merge` (`SKILL.md:83`).
   `codex-execution-handoff` prescribes merge → deploy → verify-on-prod (`SKILL.md:44`) and states it
   "deliberately overrides that". The story doc and the kickoff prompt hand the executing agent
   opposite instructions.

2. **Planning cannot call handoff.** `sprint-orchestrator` sets `disable-model-invocation: true`
   (`SKILL.md:4`), so no model can invoke it — yet `codex-execution-handoff:86` says
   "**REQUIRED BACKGROUND:** invoke `sprint-orchestrator`". That instruction is unfulfillable.

3. **The lifecycle is written three times per sprint.** Once generically in the skill; again in a
   hand-authored ~100-line `docs/sprints/<sprint>/HANDOFF.md`; again inside every story doc's
   `## Goal`. They drift.

4. **Story state is fiction, in both directions.** The claim rename is bundled into the story's own
   feature commit on the story's own branch — `8c72724 feat(reports): add date range presets`
   contains `rename 07-date-presets.md => 07-date-presets.CLAIMED.md` — so it reaches trunk only when
   the story merges. On `origin/main`, ten docs read `.CLAIMED.md` while shipped, and
   `10-alerts-analyzer.md` reads TODO while `sprint/10-alerts-analyzer` is checked out in a live
   worktree.

5. **`done/` has never been used.** Zero times across 18 stories in two sprints. It does not exist on
   `origin/main`.

6. **Screenshot evidence rots.** Codex obeyed "capture before/after screenshots" by writing to
   `/tmp/strix-*.png`. Every Evidence line in `STORY-FEEDBACK.md` points outside the repo.

7. **The executor's environment fights the doc-as-state model.** `STORY-FEEDBACK.md:95` records that
   Story 04's worktree did not contain the sprint docs at all; Codex copied `00-overview.md`,
   `STORY-FEEDBACK.md`, and its story doc in from `~/lead-us` before starting. The note warns this
   "can affect all report-delivery story sessions."

Smaller: the template has drifted from real usage (real docs carry `wave:`, `owns_hunk:`,
`shared_note:`, and a `## Browser Verification` section the template never mentions but the handoff
depends on — 10 of 10 stories have one); and `Find Open Stories` globs `[0-9][0-9]-*.md`, which fails
on `06b-target-header-scale.md`.

## Decisions

| # | Decision |
|---|----------|
| 1 | Merge authority is per-sprint: `execution: autonomous \| stop-at-pr` |
| 2 | No binding file. Project facts come from the project's `AGENTS.md` / `CLAUDE.md` |
| 3 | The planner generates a conversation title; the handoff transports it |
| 4 | Evidence is rendered inline in Codex.app's final message. Asana attachment is impossible |
| 5 | Story state is **derived**, never stored. Nothing is renamed or moved |
| 6 | A `Story: NN` commit trailer is the durable done-signal |
| 7 | Both skills move into `~/claude-skills`, symlinked into Claude and Codex |
| 8 | A screenshot from an **approved driver** is mandatory; a DOM assertion never substitutes |

## Design

### 1. Skill boundary

**`sprint-orchestrator` — planning.** Keeps: the verification contract, plan session, story-doc
template, tracker binding (`card.create`), sprint status, planning guardrails. It loses `Claim And
Run` entirely, and loses the mechanical half of `Integrate`.

`Integrate` does not split cleanly, so state where each half goes. Planning keeps the planning
outputs: **merge order and shared-file hotspots are decided at plan time and recorded in
`00-overview.md`**, and **sweeping `STORY-FEEDBACK.md` for follow-up stories** is a plan-session
activity. Execution takes the mechanical parts: performing the merge in that order, resolving the
named hotspots, deploying, and `card.done`.

**`codex-execution-handoff` — execution protocol and prompt renderer.** Owns: the lifecycle, the
`/goal` late-checkpoint, the deploy gate and rollback, the evidence protocol, and the hand-back
format — in both `execution:` modes. Under `stop-at-pr` it describes the human-gated variant itself
rather than deferring to the orchestrator, so integration is documented in exactly one place.

**It is invoked by whoever plans, never by the executing story session.** The executor already has
the rendered prompt; it has no reason to read the renderer. This matters because the skill is
installed into `~/.codex/skills` (Codex sometimes plans — it planned the 2026-07-07 sprint), which
would otherwise put an authoring skill in the executor's skill list.

The per-sprint `HANDOFF.md` is deleted. The lifecycle exists once, in the skill. Project facts are
never restated: `lead-us/AGENTS.md` already carries `vercel --prod --yes`, `npx tsc --noEmit`,
`app.strixrise.com`, and a pointer to `TEST_ACCOUNTS.md`.

When a plan session finishes and `execution: autonomous`, `sprint-orchestrator` invokes
`codex-execution-handoff` to render kickoff prompts for stories whose `depends_on` are satisfied.

Two corrections fall out: the unfulfillable "invoke `sprint-orchestrator`" becomes "read the story
doc and `00-overview.md`", and the orchestrator's `do not merge` line becomes conditional on
`execution:`.

This does not shrink `sprint-orchestrator` much — it sheds roughly 40 lines (`Claim And Run`,
`Integrate`, `Filesystem State`, `Find Open Stories`) and gains roughly 20. The saving is per-sprint:
one 100-line `HANDOFF.md` and sixteen restatements of the lifecycle.

### 2. Story doc contract

Frontmatter is the interface. New and promoted fields marked:

```yaml
story: 06
title: 3-target report header
conversation: "Story 06: Monthly Target Header"   # NEW
sprint: 2026-07-07-report-delivery-sprint
execution: autonomous            # NEW — copied from 00-overview.md
flow: mechanical                 # mechanical | design-heavy
branch: sprint/06-target-header
depends_on: [05]
wave: 2                          # PROMOTED
frontend: true                   # NEW — drives the evidence requirement
surfaces:                        # NEW — required iff frontend: true; executor may extend
  - route: /reports
    states: [targets set, targets unset]
ownership:
  owns: [src/components/reports/report-header-strip.tsx]
  owns_hunk: [...]               # PROMOTED
  do_not_touch: [...]
  shared_note: ...               # PROMOTED
tracker_card:
```

`mode: shaped | open` is dropped — unused, and real docs repurposed it to `mode: claimed`.
`## Browser Verification` joins the template. Each story's `## Goal` shrinks to the `/goal` line.

`execution:` is declared once in `00-overview.md` and **copied into every story's frontmatter**. The
story doc is a prompt for a fresh agent; it must not require reading the overview to know whether it
may merge.

`conversation:` is `Story NN: <Three Descriptive Words>`, generated by the planner, used as the
kickoff prompt's first line so the Codex.app session title matches. It equals the Asana card title
convention in `lead-us/.claude/skills/asana/SKILL.md` (`Story NN: <title>`), so card and session
titles align for free.

### 3. State is derived, not stored

No `.CLAIMED.md`. No `done/`. No claim commit. Nothing to rename, so nothing to forget to rename.

Revision 1's step-0 trunk claim is impossible (see Revision history). Deriving state from branches
alone is also wrong, and the dry run proves it: a branch with zero commits reads as merged the moment
trunk advances (`sprint/10-alerts-analyzer`, live worktree, reported DONE), and a branch deleted after
merging is indistinguishable from one that never existed (Stories 01 and 04, shipped, reported TODO).
The 2026-07-07 stories were **fast-forwarded**, so no merge commit names them either.

Git holds no durable per-story signal today. One must be introduced. The executor adds a trailer to
every commit it makes for a story:

```
feat(reports): add date range presets

Story: 07
Sprint: 2026-07-07-report-delivery-sprint
```

Trailers are footers, so this composes with the existing `type(scope): description` convention. The
signal rides inside a commit the executor must make anyway — the property `.CLAIMED.md` lacked — and
survives branch deletion, fast-forward, squash, and rebase.

Status derivation, in precedence order:

| State | Signal |
|-------|--------|
| `DONE` | `git log origin/main --grep '^Story: NN'` finds a commit |
| `DOING` | a `sprint/NN-*` branch or a worktree pinned to one exists, and not `DONE` |
| `TODO` | neither |

`DONE` outranks `DOING`, because merged branches and their worktrees linger — `sprint/07-date-presets`
is merged and still has a worktree pinned to it.

Story enumeration reads the sprint directory for files matching `^[0-9]`, excluding `00-*`. This
retires the `[0-9][0-9]-*.md` glob and with it the `06b-target-header-scale.md` blind spot. Branch
names, not filenames, carry identity.

Under `execution: stop-at-pr`, nothing changes: the trailer is on the branch's commits, and `DONE`
flips when the human merges.

**Legacy consequence, stated plainly.** The two existing sprints have no trailers, and their history
will not be rewritten. `sprint status` cannot tell the truth about them; their status comes from
`00-overview.md` and `STORY-FEEDBACK.md`. The derivation is correct from the next sprint onward.

**Failure modes the executor must handle, not improvise around:**

- A `sprint/NN-*` branch already exists → the story is taken. Stop and report; do not co-opt it.
- Push rejected → `git pull --rebase` once, retry once, then stop and report.
- The sprint docs are absent from the worktree (`STORY-FEEDBACK.md:95`) → read them from trunk with
  `git show origin/main:docs/sprints/<sprint>/<doc>`. Do not copy them into the worktree and do not
  commit copies.
- Never run `git checkout main`. Trunk is checked out in another worktree and the command will fail.

### 4. Evidence

The planner sets `frontend: true` and enumerates `surfaces:`. The trigger is **not** "does
`ownership.owns` include `src/components/**`" — Story 05 was `lib/` date math that changed what
`/reports` and `/dashboard` rendered. The rule is: *does any user-visible surface change?* When
unsure, set `frontend: true` and name the surface.

`surfaces:` is a floor, not a ceiling. It is knowable roughly at plan time, not exhaustively, so the
executor **must extend it** when verification reveals an affected surface the planner missed, and
record the extension in `STORY-FEEDBACK.md`.

For each `(route, state)`: **before** and **after** locally, plus **after** on the live URL. The
before-shot anchors the lifecycle step that already demands "establish the baseline BEFORE changing
anything" but today produces no artifact.

Every shot declares its provenance. Route and state are not enough:

| Surface | State | Driver | Viewport | Role | Client |
|---|---|---|---|---|---|
| `/reports` | targets set | in-app connector | 1280×720 | admin | MyWhisky |
| `/reports` | targets unset | playwright + system Chrome | 1440×900 | admin | Codex Test Client |

**Approved drivers are named in the project's `AGENTS.md`.** A screenshot from an approved driver is
mandatory. Banned unconditionally: a DOM class check standing in for a screenshot; any driver not
listed in `AGENTS.md`; and omitting which driver produced a shot. If no approved driver can drive the
flow, the story **halts and reports what it tried**.

This is revision 1's hard gate, softened on evidence. Eight of eight frontend stories in the last
sprint hit the in-app connector's auth-gated-flow timeout and fell back to Playwright Core with system
Chrome. The real defect was never the substitute tool — it was that the substitution was **silent and
degraded**: Story 08 shipped a default 1280×720 viewport proving trigger placement while its actual
colour assertion quietly downgraded to a DOM class check. Declared provenance kills that. A hard ban
would have halted the sprint eight times and bought nothing.

The `/goal` therefore carries **three** legitimate early-interrupt conditions: a wrong premise or
genuine product ambiguity; an inability to keep prod green; and an inability to verify with any
approved driver.

**Where the files go.** Not `/tmp`, and not inside the repo. Screenshots written into a Codex-managed
worktree die when that worktree is deleted, which is sooner than a reboot — a gitignored
`docs/sprints/**/evidence/` is only a softer `/tmp`. Evidence lands in
`~/.sprint-evidence/<sprint>/<NN-slug>/`, outside every worktree and outside git. This is
machine-local; it is a review-window artifact, not an archive.

**Codex.app renders images**, so the hand-back embeds the shots inline in its final message, grouped
before/after per surface. That is the confirmation step. Asana attachment is not possible and the
skill must not suggest it: the Asana V2 MCP's write tools are `create_tasks`, `create_project`,
`update_tasks`, `delete_task`, `add_comment`, `create_project_status_update` — no attachment upload —
and Asana's docs state MCP tokens do not work with the REST API, closing the `/attachments` fallback.
The written hand-back still reaches the card via `add_comment`.

With `frontend: false`, no screenshots — but a produced artifact (PDF, email, export) must still be
opened and confirmed.

### 5. Kickoff prompt

Rendered by `codex-execution-handoff` from the story doc:

1. First line: the `conversation:` title, so the Codex.app session is named for the story.
2. Preflight: refuse if a `sprint/NN-*` branch exists; cut the branch from `origin/main` **without
   checking out trunk** (`git fetch origin && git switch -c sprint/NN-slug origin/main`); confirm the
   Vercel project link before any deploy.
3. Steps: plan → implement (commits carry the `Story: NN` trailer) → validate locally → merge &
   deploy → verify on prod → hand off. Under `stop-at-pr`, merge and deploy collapse to "open a PR".
4. Reading list: the story doc, `00-overview.md`, `STORY-FEEDBACK.md`, `AGENTS.md` / `CLAUDE.md` —
   read from `origin/main` if absent from the worktree.
5. Closing `/goal`, verbatim from the story doc, naming the three interrupt conditions.

The prompt does not restate the plan, the deploy command, or the live URL.

### 6. Packaging

Both skills move into `~/claude-skills/`, joining `codex`. `install.sh` links them into
`~/.claude/skills`; `CLAUDE_SKILLS_DIR=~/.codex/skills ./install.sh` links them into Codex's skills
directory. The override already exists — no script change.

The two drifted `sprint-orchestrator` frontmatters reconcile into one, worded to cover both invocation
sigils (`/sprint-orchestrator`, `$sprint-orchestrator`). Codex's tolerance of the Claude-specific
`disable-model-invocation: true` key must be verified before symlinking; if Codex errors on unknown
keys, the skills stay separately installed and this decision reverts.

## Non-goals

- Rewriting the tracker binding. `card.create` / `card.done` stay as they are.
- A real claim lock. Branch existence is the taken-signal; a solo operator launching sessions one at
  a time does not need more.
- Rewriting git history to backfill trailers onto the two existing sprints.
- Root-causing the in-app connector's auth-gated-flow timeout. Worth doing; out of scope here.

## One-time migration

These touch `~/lead-us` and need an explicit go-ahead per item:

1. Delete `docs/sprints/2026-07-07-report-delivery-sprint/HANDOFF.md` once the skill supersedes it.
2. Rename `2026-07-02-functional-sprint/00-sprint-overview.md` to `00-overview.md`, or leave it. The
   skill names `00-overview.md`.
3. Eighteen `.CLAIMED.md` docs across the two sprints revert to plain `NN-slug.md`. Their status lives
   in `00-overview.md` / `STORY-FEEDBACK.md`; no trailers will be backfilled.
4. Record in `lead-us/AGENTS.md`: the **approved visual drivers** (in-app connector; Playwright Core
   with system Chrome), and the Vercel gotcha from `STORY-FEEDBACK.md:56` — a fresh worktree
   auto-links to the throwaway `lead-us` Vercel project whose env lacks Supabase keys and fails the
   build at `/no-access`; copy `.vercel/project.json` from the main checkout and re-pull prod env.
   Both are genuine project facts. Do **not** record "when the connector times out, use Playwright" as
   a workaround — the driver list makes Playwright legitimate, and silence about *which* driver ran is
   the thing being banned.

Separately, delete the stale copies at `~/Downloads/sprint-orchestrator-skill/` and
`~/Documents/Codex/2026-07-07/files-mentioned-by-the-user-name/outputs/sprint-orchestrator/` once
`~/claude-skills` is the source of truth.

## Risks

- **The trailer is a discipline, and disciplines decay.** It is stronger than `.CLAIMED.md` because it
  lives inside a commit that must happen, but a story whose commits omit it reads `TODO` forever. The
  deploy gate should refuse a story branch whose commits carry no `Story: NN` trailer.
- **`sprint status` is blind to other machines.** `DOING` leans on local branches and worktrees.
  Correct for a solo operator; wrong the moment a second machine or person runs a story.
- **Evidence in `~/.sprint-evidence/` is machine-local and unversioned.** Deliberate — it is a
  review-window artifact. If evidence must outlive the review, it needs a real home, and this spec
  does not give it one.
- **Declared provenance is a prompt rule, not an enforced one.** Nothing mechanically prevents an
  executor from claiming a driver it did not use. The hand-back format makes the omission visible,
  which is the most a prompt can buy.

## Success criteria

1. `sprint status <sprint>` matches reality for a sprint planned under these skills: `DOING` names the
   story with a live worktree; `DONE` names every merged story, including ones whose branch was
   deleted; `TODO` names the rest.
2. A sprint produces no `HANDOFF.md`, and no story doc restates the lifecycle.
3. A frontend story's hand-back shows before/after screenshots inline for every declared
   `(route, state)`, each labelled with driver, viewport, role, and client.
4. No story ships with a DOM assertion in place of a screenshot, or with an undeclared driver.
5. `sprint-orchestrator` and `codex-execution-handoff` each exist as exactly one file on disk,
   reachable from both `~/.claude/skills` and `~/.codex/skills`, and the executing story session
   invokes neither.
6. No story doc contains both "do not merge" and a merge-and-deploy `/goal`.
7. No kickoff prompt contains `git checkout main`.
