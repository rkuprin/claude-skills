---
name: sprint-orchestrator
description: Manual sprint planning command for turning raw inputs into verified filesystem-backed story handoff docs. Invoke explicitly with /sprint-orchestrator.
disable-model-invocation: true
argument-hint: [sprint-dir or raw inputs]
---

# Sprint Orchestrator

Manual sprint-planning skill for turning raw inputs into independent story handoffs. It plans and hands off; it does not implement stories, merge branches, or declare work done.

## Contract

- Treat notes, PDFs, screenshots, and tracker cards as leads. Verify candidates against source truth: code, tests, docs, logs, and approved read-only project tools.
- Mutate only sprint planning files and tracker sink calls unless the user asks for more.
- Keep tracker state out of control flow. Tracker calls are write-only intents resolved by a project binding.
- Story state is the doc path. Do not add status frontmatter, ledger files, or tracker-derived done detection.

## Filesystem State

Use `docs/sprints/<sprint>/` unless the user gives another path.

```text
docs/sprints/<sprint>/07-<slug>.md          TODO
docs/sprints/<sprint>/07-<slug>.CLAIMED.md  DOING
docs/sprints/<sprint>/done/07-<slug>.md     DONE
```

`done/` is archive and state. A story is complete only after the human moves its doc into `done/`.

## Plan Session

1. Collect raw sprint inputs without filtering.
2. Verify every candidate against current source truth. If a premise is stale, already shipped, impossible, or out of scope, cut or reframe it and record why.
3. Split surviving work into stories by blast radius, file ownership, and dependency order. Prefer serial stories for shared hotspots over optimistic parallelism.
4. Write `00-overview.md`, `STORY-FEEDBACK.md`, and one story doc per survivor.
5. Recap open stories with kickoff prompts and any unresolved product questions.

`00-overview.md` must include merge order, dependency edges, shared file hotspots, cut items with reasons, and the path to `STORY-FEEDBACK.md`.

## Story Doc Shape

Each story doc is a prompt for fresh investigation, not a stale implementation spec. Use anchors that survive drift: symbols, behaviors, commands, queries, and files, not fragile line numbers unless the line itself is the evidence.

```markdown
---
story: 07
title: <short imperative>
sprint: <sprint-name>
flow: mechanical        # mechanical | design-heavy
mode: shaped            # shaped | open
branch: sprint/07-<slug>
depends_on: []
ownership:
  owns: [src/reports/**]
  do_not_touch: [src/app/layout.tsx]
tracker_card:
---

# Story 07 - <title>

**Kickoff:** `read docs/sprints/<sprint>/07-<slug>.md and begin`

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

## Done means
- [ ] <observable success criterion>
- [ ] If output is a file, PDF, email, export, or other artifact, a human opened it and confirmed it.

## Handoff
- On claim: rename this doc to `.CLAIMED.md`; create the tracker card if a binding exists.
- On finish: stop at PR/merge decision, do not merge, and append findings to `STORY-FEEDBACK.md`.
```

## Claim And Run

When a human starts a story session:

1. Rename `NN-<slug>.md` to `NN-<slug>.CLAIMED.md`.
2. Commit the claim if the repo workflow expects committed planning state: `chore(sprint): claim story NN`.
3. Resolve `card.create(story, sprint, branch)` through the project tracker binding and write the returned id to `tracker_card`. If no binding exists, leave it blank and mention the no-op.
4. The story session re-verifies the doc, plans with the human, executes the story, verifies, and stops at the merge gate.
5. Append useful cross-story findings to `STORY-FEEDBACK.md`.

## Integrate

Integration is human-gated:

1. Merge in the order from `00-overview.md`.
2. Resolve named hotspots by hand.
3. After a story lands, move `NN-<slug>.CLAIMED.md` to `done/NN-<slug>.md`.
4. Resolve `card.done(card_id)` through the tracker binding.
5. Sweep `STORY-FEEDBACK.md` for follow-up stories or stakeholder questions.

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

If `tracker: none`, no binding exists, or the named MCP/tool is unavailable, tracker intents are no-ops. Report the intended `card.*` action in the recap and leave `tracker_card` blank. The filesystem remains the ledger.

## Find Open Stories

To reprint active kickoff prompts, run this manual helper from the repo root:

```bash
sprint="docs/sprints/<sprint>"
for f in "$sprint"/[0-9][0-9]-*.md; do
  [ -e "$f" ] || continue
  case "$(basename "$f")" in 00-*) continue ;; esac
  state=TODO
  case "$f" in *.CLAIMED.md) state=DOING ;; esac
  printf '[%s] %s\n' "$state" "$f"
  grep -m1 '^\*\*Kickoff:\*\*' "$f"
  printf '\n'
done
```

Do not scan `done/`; absence from the active set is the done signal.

## Guardrails

- If verification contradicts a story premise, stop and report the contradiction before building around it.
- If two stories want the same files, update `00-overview.md` so they run serially or split ownership clearly.
- `.CLAIMED.md` is a convention, not a lock. If multiple humans drive sessions, add a real lock or per-session planning folder before parallelizing claims.
- For artifact-returning work, mocked tests are not enough. Human inspection of the produced artifact is part of done.
