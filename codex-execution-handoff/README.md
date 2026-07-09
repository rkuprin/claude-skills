# codex-execution-handoff

Renders a kickoff prompt that hands **one** planned story to an autonomous coding agent, which runs
the whole lifecycle — plan → build → validate → merge → deploy → verify on the live app — and checks
back **once**, at a `/goal` checkpoint kept deliberately late.

Companion to [`sprint-orchestrator`](../sprint-orchestrator/), which writes the story docs this runs on.

## What it is, and what it is not

It is a **prompt renderer for whoever plans**. It is never invoked by the executing story session —
that session already holds the rendered prompt and has no reason to read the renderer.

It is not a wrapper around Codex. It produces text you paste.

## Prerequisites

**Codex.app, not the Codex CLI.** The hand-back embeds before/after screenshots inline in its final
message, which is the human's confirmation step. A terminal cannot render them.

**The consuming project's `AGENTS.md` / `CLAUDE.md` must supply:**

- the deploy command and the live URL;
- the typecheck and production-build commands that gate every deploy;
- a path to test accounts;
- **the list of approved visual-verification drivers.**

Nothing is restated in this skill. Project facts live in the project.

## Use it

Once per story, from the project's repo root:

```bash
/codex-execution-handoff docs/sprints/<sprint>/07-date-presets.md
```

Copy the rendered prompt into a **fresh Codex.app session**. Its first line is the story's
`conversation:` value — `Story 07: Report Date Presets` — so the session names itself, matching the
story's tracker card.

Under `execution: autonomous`, the agent merges, deploys, and verifies on prod. Under
`execution: stop-at-pr`, the same lifecycle runs but it opens a PR and stops. The mode comes from the
story doc, which inherited it from `00-overview.md`.

## The `/goal` late-checkpoint

The prompt ends with one `/goal` line stating the story's concrete, observable success on the live
app — not "tests pass". It is the first point the agent checks back. It surfaces earlier for exactly
three reasons:

1. a wrong premise or genuine product ambiguity;
2. an inability to keep prod green;
3. no approved driver can drive the browser verification.

## What the agent must do

**Never `git checkout main`.** Trunk is often checked out in another worktree, so the command fails.
It cuts its branch with `git switch -c sprint/NN-slug origin/main`. If that branch already exists, the
story is taken: stop, do not co-opt it.

**Every commit carries two trailers** — `Story: NN` and `Sprint: <sprint-dir-basename>`. This is the
only record that the story landed; `sprint-status.sh` derives `DONE` from it. The deploy gate checks
for both, so an untrailered story cannot ship.

**Never leave prod broken.** Tests, typecheck, and a production build gate every deploy. A failed live
check that is not a fast fix means roll back or revert, then report.

## Screenshots

A story is `frontend: true` when any user-visible surface changes — including a pure `lib/` change
that alters what a page renders. The planner lists `surfaces:` as `(route, states)`; the executor
treats that as a **floor** and extends it when verification reveals a surface the planner missed.

For each `(route, state)`: before and after locally, plus after on the live URL. Every shot declares
its driver, viewport, role, and client. A DOM class check never substitutes for a screenshot, and a
driver not named in `AGENTS.md` is not allowed. If no approved driver can drive the flow, the story
halts and reports what it tried.

Files land in `~/.sprint-evidence/<sprint>/<NN-slug>/` — never `/tmp`, and never inside a git worktree,
which is deleted long before a reboot and takes the evidence with it.

Tracker attachment is not possible: the Asana V2 MCP exposes no attachment-upload tool, and its tokens
do not work with the REST API. The written hand-back reaches the card via `add_comment`.

## Tests

From this repo: `test/lint-skills.sh`

The lint greps this file for invariants — that the deploy gate names both trailers, that the `/goal`
example lists all three interrupt conditions, that `git checkout main` appears only when negated, and
that no per-sprint `HANDOFF.md` or `.CLAIMED.md` machinery has crept back in. Prose is the product,
so the prose is linted.
