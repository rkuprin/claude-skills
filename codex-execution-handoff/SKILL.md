---
name: codex-execution-handoff
description: Use when handing a planned, self-contained story to an autonomous coding agent (e.g. Codex) that should implement it, ship it to prod, verify on the live app, and report back once — instead of stopping at a PR for review. Pairs with the sprint-orchestrator story-doc format. Triggers: "hand this to Codex", autonomous execution, merge+deploy+verify, run a story end-to-end.
---

# Codex Execution Handoff

## Overview

Hand ONE planned story to an autonomous coder that runs the whole lifecycle — plan → build → validate → **merge to trunk → deploy to prod → verify on the live app** — and pings you **once**, at a story-specific `/goal` checkpoint kept **as late as possible**.

Companion to `sprint-orchestrator`, which writes the story docs; this skill is the execution-and-handoff half. A capable agent already handles the generic "work autonomously, report once" shape on its own. This skill exists for the parts that are easy to get wrong: the **`/goal` late-checkpoint**, **merge→deploy→verify-on-prod** (not deploy-from-a-branch), the **deploy gate + rollback**, and the **structured hand-back**.

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

Fill `{STORY_DOC}`, the verify/deploy commands, and the live URL; end with the story's `/goal`.

```
You are executing ONE story. Run the full lifecycle below: plan, build, validate, then MERGE and DEPLOY TO
PROD, verify on prod, and hand it back to me (Rodion) with test instructions.

Read first: {STORY_DOC}, the sprint overview (scope, locked decisions, parallelism, merge order, your ownership
lane), the shared feedback log, and the repo conventions (AGENTS.md / CLAUDE.md). The product scope and product
decisions in those docs are SETTLED — treat them as fixed. If you find a wrong premise, an internal
contradiction, or a genuine product ambiguity, STOP and ask me. Otherwise proceed.

1. PLAN — brainstorm your own approach (design-heavy: weigh 2-3 options; mechanical: a short TDD plan). Do the
   doc's "Start by verifying"; reproduce the bug / establish the baseline BEFORE changing anything. Restate In/Out of scope.
2. IMPLEMENT — branch = the doc's branch; claim the doc (rename to .CLAIMED.md, move its tracker card to In
   Progress). TDD: failing test first. Stay strictly inside `ownership.owns`; never touch `do_not_touch`. Follow repo conventions.
3. VALIDATE LOCALLY — run tests + typecheck; drive the doc's Browser Verification locally where feasible;
   capture before/after screenshots for anything visual; open any produced artifact. Fix until green.
4. MERGE & DEPLOY — gate: tests + typecheck + a production build must all pass; do NOT deploy a broken build.
   Merge into the trunk in the overview's merge order; ensure trunk is green. Deploy with the deploy command.
5. VERIFY ON PROD — drive the Browser Verification against the LIVE URL with a real test account; capture prod
   screenshots. Defect -> fix, re-gate, redeploy, re-check. If prod breaks and it isn't a fast fix -> roll back
   (or revert the merge) and tell me. Never leave prod broken.
6. HAND OFF — append findings to the shared feedback log; produce the "How to test this yourself" section
   (below); move the tracker card to Done; state branch, files, tests + results, deploy id.

Finally — this is your goal and the first (ideally only) point you check back with me. Work the whole lifecycle
autonomously toward it; only surface earlier on a wrong premise / product ambiguity, or if you can't keep prod green.

/goal {STORY_GOAL}
```

## Deploy gate + rollback (non-negotiable)
- Gate EVERY deploy on: story tests + typecheck + a production build. A broken build never reaches prod.
- If the live check fails and isn't a fast fix: roll back the deploy (or revert the merge) and report. Never leave prod broken.

## The "How to test this yourself" hand-back format
What changed · Where = live URL + role/account · Steps (exact clicks/inputs, expected vs observed on prod) · Test data/accounts · Evidence (prod screenshots/GIF) · Risk + how to roll back · Checks run (commands + results, build, deploy id) · Open questions.

## Common mistakes
- **Deploying from a feature branch** instead of merging to trunk first — "live" then ≠ what you tested.
- **A `/goal` that's an early checkpoint** ("open a PR") → the agent pings you before it's live.
- **No explicit failure/rollback exit** → the agent loops forever or ships broken and reports "done".
- **Progress pings mid-run** → defeats the single-checkpoint purpose.
- **Restating the whole plan in the prompt** instead of pointing to the story doc.

## Companion: sprint-orchestrator
The story doc supplies objective, ownership (`owns` / `do_not_touch`), done-criteria, and the claim protocol
(`.CLAIMED.md`, tracker card, merge order). This skill supplies the execution lifecycle and the `/goal`.
**REQUIRED BACKGROUND:** invoke `sprint-orchestrator` to produce or read the story docs this handoff runs on.
Note: `sprint-orchestrator`'s default handoff is "stop at PR, do not merge" — this skill deliberately overrides
that for autonomous, pre-real-users prod.
