---
name: sprint-orchestrator
description: Manual sprint planning command turning raw inputs into verified, git-derived story handoff docs. Invoke explicitly with /sprint-orchestrator (Claude) or $sprint-orchestrator (Codex).
disable-model-invocation: true
argument-hint: [sprint-dir or raw inputs]
---

# Sprint Orchestrator

Manual sprint-planning skill for turning raw inputs into independent story handoffs. It plans and hands off; it does not implement stories, merge branches, or declare work done.

## Run This on the Strongest Model

Sprint planning gets the most capable model available. First, name the model you are running as.
If it is not the strongest tier reachable right now (today: Fable, else Opus, on Claude Code; Sol
at ultra effort on Codex), say so and offer to stop so the user can relaunch. No hard block — but
proceeding on a lesser model needs the user's explicit go-ahead, recorded in `00-overview.md`.

## Contract

- Treat notes, PDFs, screenshots, and tracker cards as leads. Verify candidates against source truth: code, tests, docs, logs, and approved read-only project tools.
- Mutate only sprint planning files and tracker sink calls unless the user asks for more.
- Keep tracker state out of control flow. Tracker calls are write-only intents resolved by a project binding.

## Story State Is Derived

Story state is never written down. It is computed from git, so it cannot drift.

| State | Signal |
|-------|--------|
| `DONE` | one commit reachable from trunk carries **both** `Story: NN` and `Sprint: <sprint-dir-basename>` |
| `DOING` | a `sprint/NN-*` branch or a worktree pinned to one exists, and not `DONE` |
| `TODO` | neither |

Both trailers, on the same commit. `Story: NN` alone is not enough: story numbers restart every
sprint, so a bare `Story: 07` match would make the next sprint's story 07 read `DONE` on day one.

`DONE` outranks `DOING`: merged branches and the worktrees pinned to them linger long after the
work lands.

The trailer is a footer on every commit the executor makes for a story, so it survives branch
deletion, fast-forward, squash, and rebase:

```
feat(reports): add date range presets

Story: 07
Sprint: 2026-07-07-report-delivery-sprint
```

`Sprint:` is the sprint directory's basename, verbatim — for `docs/sprints/2026-07-07-report-delivery-sprint`,
that's `2026-07-07-report-delivery-sprint`, not a shortened form or the tracker's sprint name.
`sprint-status.sh` matches it exactly against the directory it's given, so any other string makes
every story in that sprint read TODO forever.

Read the current state with the `sprint-status.sh` helper that sits beside this skill file, from
the repo root. It is the same script reached via either agent's skills directory:

```bash
~/.claude/skills/sprint-orchestrator/sprint-status.sh docs/sprints/<sprint>   # Claude
~/.codex/skills/sprint-orchestrator/sprint-status.sh docs/sprints/<sprint>    # Codex
```

Stories are enumerated from files matching `[0-9]*.md`, skipping `00-*`. Suffixed numbers such as
`06b` are first-class.

Sprints planned before this convention have no trailers and their history is not rewritten. For
those, `00-overview.md` and `STORY-FEEDBACK.md` are the record; `sprint-status.sh` will
under-report them and that is expected.

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

`00-overview.md` must include merge order, dependency edges, shared file hotspots, cut items with reasons, and the path to `STORY-FEEDBACK.md`.

## Integration Is Planned Here, Performed Elsewhere

Planning decides and records in `00-overview.md`: the merge order, the dependency edges, and the
shared-file hotspots that force stories to run serially. Sweeping `STORY-FEEDBACK.md` for follow-up
stories and unresolved product questions is also a plan-session activity.

Performing the merge in that order, resolving the named hotspots, deploying, and closing the tracker
card belong to `agent-handoff`'s execution contract (`EXECUTION.md`). Do not restate the lifecycle here.

## Drivers

Codex leans mechanistic, devops, and browser-driving work; Claude leans creative, frontend-heavy,
ambiguous work. Frontend visual validation renders only in Codex.app. Capability outranks affinity
— a frontend story implemented on Claude still ends with a visual-validation handoff to Codex.app;
affinity routes stages, not just whole stories. Beyond these lines, use judgment.

`driver_hint:` derives from the work's nature ONLY — never from today's capacity. The driver is
resolved at handoff time: required capability → the user's explicit say → current availability →
affinity.

## Story Doc Shape

Each story doc is a prompt for fresh investigation, not a stale implementation spec. Use anchors that survive drift: symbols, behaviors, commands, queries, and files, not fragile line numbers unless the line itself is the evidence.

```markdown
---
story: 07
title: <short imperative>
conversation: "Story 07: Three Descriptive Words"
sprint: <sprint-name>        # this sprint directory's basename, copied verbatim into every commit's Sprint: trailer
execution: autonomous        # autonomous | stop-at-pr — copied from 00-overview.md
flow: mechanical             # mechanical | design-heavy
loop: full                   # full | direct — planning depth only; the lifecycle contract is identical
driver_hint: codex           # codex | claude | either — affinity from work nature only; resolved at handoff time
driver_why: <one line tying the hint to the work's nature>
branch: sprint/07-<slug>
depends_on: []
wave: 1
frontend: true               # does any user-visible surface change?
surfaces:                    # required iff frontend: true; the executor may extend it
  - route: /reports
    states: [populated, empty]
ownership:
  owns: [src/reports/**]
  owns_hunk:
    - src/app/(app)/reports/page.tsx  # ONLY the <ReportHeaderStrip> props
  do_not_touch: [src/app/layout.tsx]
  shared_note: >
    <what a neighbouring story owns in a file this story must read but not modify>
tracker_card:
---

# Story 07 - <title>

**Kickoff (planner only — the executor does not run this):** render this story's prompt with
`agent-handoff` (story-execution mode) for `07-<slug>.md`, then hand the rendered prompt to the executor.

## Goal
<the single /goal line, nothing else>

## Objective
<Question to investigate, not the answer to implement.>

## Start by verifying
- <current code/doc/test/tool anchor to check first>

## Decisions already made
- <settled product or architecture decisions>

## In scope
- <work owned by this story>

## Out of scope
- <adjacent work and owning story>

## Browser Verification
1. <route, state, and what a human must see>

## Done means
- [ ] <observable success criterion>
- [ ] If output is a file, PDF, email, export, or other artifact, a human opened it and confirmed it.
```

`conversation:` is `Story NN: <Three Descriptive Words>`, written by the planner. It matches the
tracker's card-title convention, so the card and the executor's session share one name.

`execution:` is declared once in `00-overview.md` and copied into every story. A story doc is a
prompt for a fresh agent; it must not require reading the overview to learn whether it may merge.

`frontend:` is true when any user-visible surface changes — not when `ownership.owns` happens to
contain component paths. A pure `lib/` change that alters what a page renders is a frontend story.
When unsure, set it true and name the surface.

## Tracker Binding

If the project wants tracker writes, define the binding once in `.sprint/tracking.md`, project instructions, or another user-specified file. Discovery order is: a path named by the user, then `.sprint/tracking.md`, then a clearly labeled tracker binding in project instructions. If no binding exists, use `tracker: none`.

```yaml
tracker: asana        # asana | monday | none
project_gid: "..."
status_map:
  doing: "In Progress"
  done: "Done"
mcp: asana
```

Supported intents:

- `card.create(story, sprint, branch)` creates a card in the doing bucket and returns an id.
- `card.done(card_id)` moves that card to done.

If `tracker: none`, no binding exists, or the named MCP/tool is unavailable, tracker intents are no-ops. Report the intended `card.*` action in the recap and leave `tracker_card` blank. Nothing is lost: story state is derived from git, not from the tracker, so `sprint-status.sh` stays authoritative whether or not a tracker exists.

## Guardrails

- If verification contradicts a story premise, stop and report the contradiction before building around it.
- If two stories want the same files, update `00-overview.md` so they run serially or split ownership clearly.
- For artifact-returning work, mocked tests are not enough. Human inspection of the produced artifact is part of done.
