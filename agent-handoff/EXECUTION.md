# Execution contract — one sprint story, end to end

You are executing ONE planned story. Your kickoff prompt names the story doc, the sprint, your
EXECUTION MODE, and your `/goal`. This contract is the how. Product scope and decisions in the
story doc and `00-overview.md` are settled by default; the operator may amend them live at the
brainstorm gate, and every amendment is recorded in STORY-FEEDBACK.md. If you find a wrong
premise, an internal contradiction, or a genuine product ambiguity, follow "Divergences and
handback" below — never build around a broken premise.

## 0. Preflight

- `git fetch origin`
- If this story's designated branch — the story doc's exact `branch:` value — already exists on
  any ref, the story is taken. STOP and report; never co-opt someone else's branch. Story numbers
  restart every sprint, so a bare `sprint/{NN}-*` match false-positives on previous sprints.
- `git switch -c "{BRANCH}" origin/main` — use the story doc's exact `branch:` value. NEVER run `git checkout main`: trunk is checked
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
3. Release the claim — only if the branch is still a pure claim (no story commits): remove your
   worktree if you created one, then delete the story doc's exact `branch:` value. The story reads TODO
   again. If story commits already exist (the wrong-premise interrupt fired mid-implementation),
   keep the branch and worktree and name the branch and its last commit in the REPLAN event —
   the story reads DOING until the planner disposes of it.
4. Stop. Tell the operator to re-invoke `/sprint-orchestrator` on the sprint directory; the next
   plan session resolves the event before planning anything else. Under stop-at-pr the docs PR
   from step 2 must merge BEFORE that re-invocation — the planner sweep reads trunk, and an
   unmerged event is invisible to it; say so in your stop report.

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
- Checking or deleting `sprint/NN-*` instead of the story doc's exact sprint-scoped `branch:` value.
- Force-pushing after a rejected push. Rebase once, retry once, then stop.
- Deploying from a feature branch instead of merging to trunk first — "live" then ≠ what you
  tested.
- Silently swapping browser drivers — legal only if AGENTS.md approves the driver and the hand-back
  declares it.
- Writing evidence to `/tmp` or into the worktree — both vanish before review.
- Progress pings mid-run — defeats the single-checkpoint purpose. The brainstorm gate (step 2)
  is the sanctioned exception, and it ends when the operator says proceed.
