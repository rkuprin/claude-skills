---
name: codex-execution-handoff
description: Use when handing a planned, self-contained story to an autonomous coding agent (e.g. Codex) — `autonomous` merges, deploys, verifies on prod, and reports back once; `stop-at-pr` runs the same lifecycle but opens a PR and stops. Pairs with the sprint-orchestrator story-doc format. Triggers: "hand this to Codex", autonomous execution, merge+deploy+verify, run a story end-to-end.
---

# Codex Execution Handoff

## Overview

Render a kickoff prompt that hands ONE planned story to an autonomous coder, which runs the whole
lifecycle — plan → build → validate → merge to trunk → deploy → verify on the live app — and pings
the human **once**, at a story-specific `/goal` checkpoint kept as late as possible.

This skill is a prompt renderer for whoever plans. It is **never invoked by the executing story
session**, which already holds the rendered prompt and has no reason to read the renderer.

Companion to `sprint-orchestrator`, which writes the story docs this runs on. That skill is manual
only (`disable-model-invocation: true`), so read its story doc and `00-overview.md` directly rather
than trying to invoke it.

## When to use
- You have a planned story (via `sprint-orchestrator` or similar) and want an autonomous agent to take it all the way to live, not stop at a PR.
- Early-stage / pre-real-users prod where the agent may merge + deploy itself.
- You want to look exactly once, at the end.

## When NOT to use
- Real production with users where a human must gate every deploy → keep the "stop at PR, do not merge" handoff instead.
- Exploratory work with no clear observable done-criteria.

## The `/goal` late-checkpoint — the core idea

End the kickoff prompt with one `/goal <statement>`. Write it so DONE equals the **deployed-and-verified end state**, making it the **first** point the agent checks back — deliberately as late as possible. It MUST:
- state the story's concrete, **observable** success (what the user sees working on the live app), not "tests pass";
- require **merged + deployed + verified on the live URL**, with the how-to-test writeup ready;
- name the only legitimate early interrupts: a **wrong premise / genuine product ambiguity**, or being **unable to keep prod green**.

```
BAD  (early checkpoint):  /goal implement the fix and open a PR for me.
GOOD (late checkpoint):   /goal Story NN is done — the first point you check back with me — only when
<observable behavior> works on <live URL>, tests cover it, it's merged + deployed + verified there, and the
"how to test yourself" writeup is ready. Work plan → build → validate → merge → deploy → verify autonomously;
don't stop for intermediate approval. Interrupt earlier only for a wrong premise / genuine product ambiguity,
or if you can't keep prod green (roll back and tell me).
```

## The kickoff prompt (template)

First line is the story's `conversation:` value, so the Codex.app session takes the story's name.
Fill `{STORY_DOC}`, `{NN}`, `{SLUG}`, `{SPRINT}` and end with the story's `/goal`.

```
Story {NN}: {Three Descriptive Words}

You are executing ONE story. Run the full lifecycle below: plan, build, validate, then MERGE and
DEPLOY TO PROD, verify on prod, and hand it back to me (Rodion) with test instructions.

Read first: {STORY_DOC}, 00-overview.md (scope, locked decisions, merge order, your ownership lane),
STORY-FEEDBACK.md, and the repo conventions (AGENTS.md / CLAUDE.md). If any of those are absent from
this worktree, read them from trunk with `git show origin/main:<path>` — do not copy them in and do
not commit copies. The product scope and decisions in those docs are SETTLED. If you find a wrong
premise, an internal contradiction, or a genuine product ambiguity, STOP and ask me.

0. PREFLIGHT.
   - `git fetch origin`
   - If `sprint/{NN}-{SLUG}` already exists on any ref, the story is taken. STOP and report; never
     co-opt someone else's branch.
   - `git switch -c sprint/{NN}-{SLUG} origin/main`
     NEVER run `git checkout main`. Trunk is checked out in another worktree and the command fails.
   - Confirm this worktree is linked to the real Vercel project before any deploy (see AGENTS.md).

1. PLAN — brainstorm your own approach (design-heavy: weigh 2-3 options; mechanical: a short TDD
   plan). Do the doc's "Start by verifying"; reproduce the bug / establish the baseline BEFORE
   changing anything, capturing the "before" screenshots while you are there. Restate In/Out of scope.

2. IMPLEMENT — TDD: failing test first. Stay strictly inside `ownership.owns`; never touch
   `do_not_touch`. Every commit you make for this story carries the trailer:

       Story: {NN}
       Sprint: {SPRINT}

   This is the only record that the story landed. A commit without it is invisible to sprint status.

3. VALIDATE LOCALLY — tests + typecheck; drive the doc's Browser Verification locally; capture the
   "after" screenshots; open any produced artifact. Fix until green.

4. MERGE & DEPLOY — gate: story tests + typecheck + a production build must all pass, and the story's
   commits must carry the `Story: {NN}` trailer. Merge into trunk in the overview's merge order;
   ensure trunk is green. If the push is rejected because another session landed first, run
   `git pull --rebase` and retry ONCE. If it is rejected again, STOP and report — do not force-push
   and do not keep retrying. Deploy with the project's deploy command.

5. VERIFY ON PROD — drive the Browser Verification against the LIVE URL with a real test account;
   capture prod screenshots. Defect -> fix, re-gate, redeploy, re-check. If prod breaks and it is not
   a fast fix -> roll back (or revert the merge) and tell me. Never leave prod broken.

6. HAND OFF — append findings to STORY-FEEDBACK.md, including any surface you had to add to
   `surfaces:`. Produce the "How to test this yourself" section. Move the tracker card to Done. State
   branch, files, tests + results, deploy id.

Finally — this is your goal and the first (ideally only) point you check back with me. Work the whole
lifecycle autonomously toward it. Surface earlier ONLY for: a wrong premise or genuine product
ambiguity; an inability to keep prod green; or if no approved driver can drive the browser
verification.

/goal {STORY_GOAL}
```

Under `execution: stop-at-pr`, steps 4 and 5 collapse to: open a PR, do not merge, do not deploy.
The trailer still goes on the commits; `DONE` flips when the human merges.

## Deploy gate + rollback (non-negotiable)
- Gate EVERY deploy on: story tests + typecheck + a production build + the `Story: NN` trailer being
  present on the story's commits. A broken build never reaches prod, and an untrailered story is
  invisible to sprint status.
- If the live check fails and is not a fast fix: roll back the deploy (or revert the merge) and
  report. Never leave prod broken.

## Evidence (frontend stories)

`surfaces:` in the story doc is a floor, not a ceiling. It is knowable roughly at plan time, not
exhaustively. When verification reveals a surface the planner missed, add it, capture it, and record
the addition in STORY-FEEDBACK.md.

For each `(route, state)`: **before** and **after** locally, plus **after** on the live URL.

A screenshot from an **approved driver** is mandatory. The project's AGENTS.md names which drivers
are approved. Banned unconditionally:

- a DOM class or attribute check standing in for a screenshot;
- any driver not listed in AGENTS.md;
- omitting which driver produced a shot.

If no approved driver can drive the flow, HALT and report what you tried. Every shot declares its
provenance:

| Surface | State | Driver | Viewport | Role | Client |
|---|---|---|---|---|---|
| `/reports` | targets set | in-app connector | 1280x720 | admin | MyWhisky |

Files land in `~/.sprint-evidence/{SPRINT}/{NN}-{SLUG}/`. Never `/tmp`, and never inside a git
worktree — a worktree is deleted long before a reboot, taking the evidence with it.

**This skill targets Codex.app, which renders images.** The hand-back embeds the screenshots inline
in its final message, grouped before/after per surface. That is the human's confirmation step. Do not
attempt to attach them to the tracker card: the Asana V2 MCP exposes no attachment-upload tool and
its tokens do not work with the REST API. The written hand-back reaches the card via `add_comment`.

With `frontend: false`, no screenshots — but a produced artifact (PDF, email, export) must still be
opened and confirmed.

## The "How to test this yourself" hand-back format
What changed · Where = live URL + role/account · Steps (exact clicks/inputs, expected vs observed on
prod) · Test data/accounts · Evidence (inline screenshots + the provenance table) · Risk + how to roll
back · Checks run (commands + results, build, deploy id) · Open questions.

## Common mistakes
- **Never run `git checkout main`** — trunk lives in another worktree; the command fails. Use `git switch -c <branch> origin/main`.
- **Commits without the `Story: NN` trailer** — the story ships and sprint status still calls it TODO.
- **Co-opting an existing `sprint/NN-*` branch** instead of stopping. It means someone else has the story.
- **Force-pushing after a rejected push.** Rebase once, retry once, then stop and report.
- **Deploying from a feature branch** instead of merging to trunk first — "live" then ≠ what you tested.
- **A `/goal` that is an early checkpoint** ("open a PR") → the agent pings before it is live.
- **Silently swapping browser drivers** — the substitution is legal only if AGENTS.md approves the driver and the hand-back declares it.
- **Writing evidence to `/tmp` or into the worktree** — both vanish before review.
- **Progress pings mid-run** → defeats the single-checkpoint purpose.
