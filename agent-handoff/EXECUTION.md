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
