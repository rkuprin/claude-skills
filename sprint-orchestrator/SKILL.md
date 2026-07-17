---
name: sprint-orchestrator
description: Manual sprint command that plans verified story handoffs, dispatches them, supervises the wave to conclusion, and integrates results. Invoke explicitly with /sprint-orchestrator (Claude) or $sprint-orchestrator (Codex).
disable-model-invocation: true
argument-hint: [sprint-dir or raw inputs]
---

# Sprint Orchestrator

Manual sprint skill: it plans verified story handoffs, dispatches them, supervises the wave to
conclusion, and integrates the results. In-session execution is sanctioned in exactly two
shapes — firing approved `loop: direct` stories as subagents after the user approves the recap
(see Executing Direct Stories In-Session), and rescuing a problem story under an ownership
transfer (see Supervising the Wave). Everything else is dispatched.

## Contract

- Treat notes, PDFs, screenshots, and tracker cards as leads. Verify candidates against source truth: code, tests, docs, logs, and approved read-only project tools.
- Planning writes touch only sprint planning files and tracker sink calls. Integration adds
  exactly two more: merging story branches per the story's execution mode, and rescue commits
  under an ownership transfer — both bound by EXECUTION.md.
- Keep tracker state out of control flow. Tracker calls are write-only intents resolved by a project binding.

## Point of Contact

The user talks to the orchestrator; executors talk to it through the mailbox. The user enters a
story session only when the plan routed an interactive (`loop: full`) story there. Cross-story
decisions, priority calls, and product questions land here, not in executor threads.

## Story State Is Derived

Story state is never written down. It is computed from git, so it cannot drift.

| State | Signal |
|-------|--------|
| `DONE` | one commit reachable from trunk carries **both** `Story: NN` and `Sprint: <sprint-dir-basename>` |
| `DOING` | the story doc's exact `branch:` exists locally, remotely, or in a worktree, and not `DONE` |
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

## The Sprint Brief

What exists in the sprint directory decides how a session opens:

- **Undefined** — no sprint directory, or one holding neither story docs nor `00-overview.md`:
  discuss the sprint with the user first — what it is about, what is in, what is out, what done
  looks like. Print a **Sprint brief** on screen in colloquial, simple English and iterate until
  the user approves it. Until then nothing else happens: no verification sweep, no story docs,
  no writes. The approved brief lands verbatim as the opening `## Sprint brief` section of
  `00-overview.md`.
- **Legacy** — `00-overview.md` exists without a `## Sprint brief` section: skip the gate and
  do not force a backfill; the overview as written is the scope boundary. Backfill only if the
  user asks.
- **Partial** — story docs or `STORY-FEEDBACK.md` exist but `00-overview.md` does not: stop and
  ask the user how to recover. Never run first-run creation over an existing partial directory.

On every re-invocation of a defined sprint, re-read the brief (when present) as the boundary
all planning stays inside. The brief is the one human-facing artifact; the rest of the overview
and the story docs stay dense and agent-facing.

## Plan Session

This is high-level planning backed by in-depth research — never per-story implementation planning.
`loop: full` (default): the story's execution session opens with read-only investigation and an
interactive brainstorm with the operator before any code — the story doc is the input to that
brainstorm, not a replacement for it. `loop: direct`: the story is simple enough to define fully
here; the executor goes straight to a short TDD plan, and the story may be delegated to a cheaper
transport (subagent, `codex exec`, `claude -p`). Either way the lifecycle contract is identical —
`loop:` never waives trailers, branch discipline, or gates.

`loop:` is a judgment call, not a tier rule — the planner owns it. The recap shows every
story's `loop:` before dispatch, so the user can veto there. Brainstorm (`full`) when
the design space is open (multiple valid approaches with genuinely different trade-offs), when
investigation could plausibly reshape the approach (novel integration, unfamiliar subsystem, a
premise this session could only verify shallowly), or when user-facing design judgment is
involved. Go `direct` when the work repeats a well-trodden in-repo pattern, is a mechanical
sweep, rename, or config change, is a bugfix whose root cause and fix shape this session already
found, or when this session already verified everything the executor would otherwise
investigate. As a tendency, not a rule: S/A stories almost always read `full`, B usually does,
C usually reads `direct`.

1. Collect raw sprint inputs without filtering.
2. Verify every candidate against current source truth. If a premise is stale, already shipped, impossible, or out of scope, cut or reframe it and record why.
3. Split surviving work into stories by blast radius, file ownership, and dependency order. Prefer serial stories for shared hotspots over optimistic parallelism.
4. Write `00-overview.md`, `STORY-FEEDBACK.md`, and one story doc per current-wave survivor; record deferred waves as stubs in the overview.
5. Ask the user how Claude/Codex capacity looks right now; note the answer in `00-overview.md` as plan-time context. Capacity never changes a `driver_hint` — it informs the recap's routing suggestions and the handoff-time resolution.
6. Recap open stories with kickoff prompts, any unresolved product questions, and the pending wave checkpoint, if any.
7. If the user approves at the recap, execute chosen `loop: direct` stories as subagents (see
   Executing Direct Stories In-Session); otherwise every story goes out as a rendered handoff.

`00-overview.md` must include merge order, dependency edges, shared file hotspots, deferred-wave stubs, cut items with reasons, and the path to `STORY-FEEDBACK.md`.

## Waves Are Planned Incrementally

Stories that can start now form wave 1 and get full story docs. Work that is blocked on wave-1
outcomes is deferred: allocate its story number, record a stub in `00-overview.md` — number,
working title, one-line intent, what blocks it, and which wave-1 outcome could reshape it — and
write no story doc yet. Wave-1 implementation changes the ground truth a deferred doc would be
written against; a doc written today would be stale by its own wave.

At each wave boundary (every story `DONE` or DISPOSED), the outgoing supervisor renders the
planner handoff (see The Planner Handoff) and the user pastes it into a fresh session. On ANY
re-invocation of an existing sprint dir — wave boundary, handback, or a landed direction story
— FIRST sweep `STORY-FEEDBACK.md` for unresolved
feedback events: every `## REPLAN — rp-YYYYMMDD-NN-<n> — Story NN`,
`## DIRECTION — dr-YYYYMMDD-NN-<n> — Story NN`, or `## DISPOSED — dp-YYYYMMDD-NN-<n> — Story NN`
block with no matching `## RESOLUTION — <id>` block.
Re-verify each against current source truth; rewrite, cut, or split the affected story docs (for
a DIRECTION dossier: plan the follow-on stories or record why not); then append the resolution as
its own immutable event — `## RESOLUTION — <id>` with a `- Resolution:` line. Never edit an existing event
block. Also check for unmerged `sprint-docs/*` branches or docs-only PRs — an event stuck behind an
unmerged PR is invisible to this sweep until it lands.

Sweep the mailbox in the same pass for terminal `concluded` outcomes no supervisor processed —
a prior session may have died between an executor's conclusion and its integration. Integrating
such a leftover comes BEFORE any planning, but never on inference: the session cannot know
whether the prior supervisor is really gone; only the operator knows. Ask interactively. The
operator's confirmation that the session ended satisfies the ownership-transfer precondition and
makes this session the successor supervisor for that conclusion; then integrate per Supervising
the Wave — verify the diff, evidence, and "Done means", merge per the story's execution mode,
run the DONE check. Without that confirmation, leave the conclusion untouched and plan nothing
that depends on it.

Only then read `sprint-status.sh` output and the rest of
`STORY-FEEDBACK.md`, give an opinion on sprint progress — what landed, what drifted, what
feedback changes the remaining plan — re-verify each stub against the now-current code, and
write the next wave's story docs, cutting or reframing stubs whose premise no longer holds.

One planner per sprint dir at a time: concurrent plan sessions collide on story numbers and
merge order. Succession, not exclusion: a demoted supervisor no longer counts as a planner.
After a direction story lands, re-enter planning in a fresh planner session, never in the
executor's thread.

## Executing Direct Stories In-Session

One of this skill's two sanctioned in-session executions — inline rescue, bound by ownership transfer, is the other (see Supervising the Wave). It never starts before the user approves the
recap — the gate exists so a bad plan is seen before it runs.

- **Publish before firing.** Commit and push the sprint planning docs (story docs,
  `00-overview.md`, `STORY-FEEDBACK.md`) to trunk first: a fresh worktree reads planning docs
  via `git show origin/main:<path>` and cannot see this session's uncommitted files. Pasted
  cross-session kickoffs have the same dependency.
- Each subagent runs ONE `loop: direct` story end-to-end in an isolated worktree from its
  rendered kickoff prompt, bound by EXECUTION.md unchanged: trailers on every commit,
  `ownership.owns` / `do_not_touch`, single writer per file. `sprint-status.sh` cannot tell the
  transports apart — state stays git-derived.
- Scheduling is the plan itself: fire only stories whose `depends_on` are DONE and whose
  ownership is disjoint from every in-flight story; shared-hotspot stories run serially in
  `00-overview.md`'s merge order.
- First failure stops the dispatch batch: report what ran and what failed, leave the failed
  branch for inspection, no automatic retries mid-batch. Disposal, re-dispatch, or rescue
  afterwards is the integrate step's judgment (see Supervising the Wave).
- Transport is resolved at handoff time, never at plan time: when Claude capacity is tight, the
  same stories render as `codex exec` prints instead. Never subagent a `loop: full` story (they
  need an interactive session); `frontend: true` stories are a poor fit — their evidence path
  ends in Codex.app visual validation.

## Supervising the Wave

Dispatch is not the end of the session — the wave is supervised to conclusion.

Parallel dispatch is constrained by merge order: under `autonomous`, executors merge
themselves, so fire in parallel only stories that are both ownership-disjoint AND
merge-order-independent. When merge order matters, use `stop-at-pr` (the supervisor merges in
order) or dispatch serially.

While the wave runs, watch the mailbox reactively — never by hand-polling. On Codex with the
sprint Stop hook installed: sweep `sprint-mail.sh list`, note the epoch (`date +%s`), then
`sprint-mail.sh arm <sprint-dir> '*-question.md *-concluded.md' 1800 <epoch>` and end the
turn — the hook wakes you on new mail or timeout; on each wake sweep ALL new mail, then
re-arm with the epoch of that sweep until the wave concludes. On Claude: run
`sprint-mail.sh wait` as a background task and re-arm the same way on each wake. Answer
executor `question`s with the plan's authority;
`note` redirects are legal only while a story has not concluded. The mailbox is never state:
DONE is still both trailers on a trunk-reachable commit, and `sprint-status.sh` never reads
the mailbox.

On each terminal `concluded` outcome, verify before integrating: the diff, the hand-back
evidence, the story's "Done means". Then:

- `stop-at-pr`, verified good → merge it, in `00-overview.md`'s merge order. The merge method
  must preserve trailers — merge commit or rebase; squash only if the squash commit message
  itself carries both trailers. Conflicts: rebase once, retry once, else stop and report. The
  done-check is `sprint-status.sh` reporting `DONE` after the merge — trailers on the feature
  branch are not the check. Then deploy and verify per the project's convention (AGENTS.md),
  and fire `card.done` only after the DONE check passes.
- `autonomous` → the executor already merged; run the same post-merge DONE check on what
  landed. A story that landed without trailers is a defect: dispose of it, or re-dispatch a
  fix under an ownership transfer.
- problems → judgment, in rising order of cost: a mailbox `note` while the story is still
  live; re-dispatch under an ownership transfer; rescue inline — take the story over under an
  ownership transfer and finish it yourself, following EXECUTION.md like any executor:
  trailers on every commit, ownership bounds, single writer per file.

## Ownership Transfer

Re-dispatch, rescue, and demotion succession operate on a branch that already exists — exactly
what the preflight refuses. Takeover is legal only through this protocol:

- Precondition: the current owner is finished — a terminal `concluded` outcome, or a transport
  confirmed dead (subagent exited; the user closed the session).
  Never take over a live executor.
- Record the transfer: branch, worktree path (if any), HEAD SHA, and what remains to be done.
- The successor's kickoff is a story-execution render carrying an explicit grant line —
  `Resume grant: resume designated branch {BRANCH} at {SHA} — {WHAT REMAINS}` — and the grant
  is the ONLY thing that overrides the branch-exists refusal; a kickoff without one still
  refuses. Inline rescue states the same grant in-session before its first commit.
- Single writer: the grant names exactly one successor; at most one authorized owner at any
  moment.

## Disposal Is an Event

A story the wave gives up on — cut, deferred, or reassigned — is recorded as an immutable
DISPOSED event in `STORY-FEEDBACK.md`, same discipline as REPLAN/DIRECTION:

    ## DISPOSED — dp-YYYYMMDD-NN-<n> — Story NN
    - Outcome: cut | deferred | reassigned
    - Cleanup: <branch / worktree / PR disposition>
    - Reason: <one line>

DISPOSED is wave accounting, never DONE: `sprint-status.sh` keeps reporting git truth, and the
next planner treats a DISPOSED story as settled intent, not unfinished work. Event IDs of all
kinds carry the story number — `rp-YYYYMMDD-NN-<n>`, `dr-YYYYMMDD-NN-<n>`, `dp-YYYYMMDD-NN-<n>`
— so parallel writers cannot collide on same-day IDs. Events already recorded keep their old
IDs; events are immutable.

## The Planner Handoff

A wave concludes when every story is DONE or DISPOSED. The next wave is never planned in this
transcript — supervision leftovers poison planning focus. Render a planner handoff for a fresh
session, then stop:

    Sprint planning continues: <sprint-basename> — wave <N+1>

    Re-invoke /sprint-orchestrator on <literal sprint path>.
    Wave <N> outcome: <one line per story — merged / disposed / leftover>.
    Leftover in flight: <story NN and who holds it | none>.
    Unresolved events: <ids | none>.
    Mailbox: <literal mailbox path> — sweep it before planning.

    /goal Wave <N+1> planned, dispatched, and supervised to conclusion — every story
    merged or disposed — and the next planner handoff rendered.

The `/goal` targets the NEXT wave boundary — a goal that ends at dispatch would recreate the
plan-and-exit behavior this lifecycle replaces.

**Early unblock.** If only a leftover story holds the wave and nothing in wave N+1 depends on
it, render the planner handoff now and demote yourself: from that moment, answer no mailbox
messages and write no planning files — story docs, `00-overview.md`, and event resolutions
belong to the fresh planner. You act solely as the leftover's executor: executor mailbox kinds,
executor-side events (a REPLAN on handback), nothing more. A demoted supervisor no longer
counts as a planner.

## Drivers

Codex leans mechanistic, devops, and browser-driving work; Claude leans creative, frontend-heavy,
ambiguous work. Frontend visual validation renders only in Codex.app. Capability outranks affinity
— a frontend story implemented on Claude still ends with a visual-validation handoff to Codex.app;
affinity routes stages, not just whole stories. Beyond these lines, use judgment.

`driver_hint:` derives from the work's nature ONLY — never from today's capacity. The driver is
resolved at handoff time: required capability → the user's explicit say → current availability →
affinity.

## The Ladder

`tier:` grades the work's difficulty; `driver_hint:` grades its nature. Tier picks the row,
driver the column. S and A have one cell each, so they bind the harness at plan time; B and C
stay late-bound. Tiers are the operator's routing policy, not an empirical ordering.

| Tier | Claude (`--model`) | Codex (`-m`) | Depth default |
|------|--------------------|--------------|---------------|
| S | `fable` | — | high (xhigh only when capability-limited) |
| A | — | `gpt-5.6-sol` | xhigh |
| B | `opus` | `gpt-5.6-terra` | xhigh |
| C | `sonnet` | `gpt-5.6-luna` | high |

Depth scale, literal on both harnesses: `low | medium | high | xhigh | max`. Depth defaults are
operator policy for today's model generation — effort levels do not port across models; revisit
the defaults when a generation changes.

Orchestration shares the launch control with depth and implies xhigh: ultracode on Claude,
`model_reasoning_effort=ultra` on Codex. Sol and Terra support `ultra`; Luna does not — an
orchestrated C-tier codex story bumps to Terra.

Grading:

- **S** — ambiguous, architectural, novel design; a wrong turn is very expensive.
- **A** — hard but well-scoped cross-cutting work, mechanistic-leaning.
- **B** — multi-file but well-trodden.
- **C** — contained mechanical work; most `loop: direct` stories.

Like `driver_hint:`, `tier:` derives from the work's nature ONLY — never from today's capacity.
For S and A, `driver_hint` must equal the tier's harness (S → `claude`, A → `codex`); `either`
is invalid there, and a contradictory pair (`tier: S` + `driver_hint: codex`) is a planning
error.

## Story Doc Shape

Each story doc is a prompt for fresh investigation, not a stale implementation spec. Use anchors that survive drift: symbols, behaviors, commands, queries, and files, not fragile line numbers unless the line itself is the evidence.

```markdown
---
story: 07
title: <short imperative>
conversation: "2026-07-07-report-delivery-sprint · Story 07: Three Descriptive Words"
sprint: <sprint-name>        # this sprint directory's basename, copied verbatim into every commit's Sprint: trailer
execution: autonomous        # autonomous | stop-at-pr — copied from 00-overview.md
flow: mechanical             # mechanical | design-heavy | direction
loop: full                   # full | direct — planning depth only; the lifecycle contract is identical
driver_hint: codex           # codex | claude | either — affinity from work nature only; resolved at handoff time
driver_why: <one line tying the hint to the work's nature>
tier: B                      # opus (claude) / gpt-5.6-terra (codex) — the letter governs; the comment is advisory
tier_why: <one line grading the difficulty>
branch: sprint/<sprint-name>/07-<slug>
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

`effort:` is written only when the story deviates from its tier's depth default, and then an
`effort_why:` line is required — an absent `effort:` means "the current row default, resolved at
render time", so defaults never go stale inside story docs:

```yaml
effort: medium
effort_why: pure mechanical sweep, low ambiguity
```

`orchestrate: true` is written only when true: the story itself is coverage-shaped and
fire-and-verify — an audit, a migration, a repo-wide sweep where missing something costs more
than compute. It implies xhigh depth; never combine it with `effort:`. Interactive or
redirectable work never gets it (orchestrated workflows cannot pause for input).

`conversation:` is `<sprint-name> · Story NN: <Three Descriptive Words>`, written by the planner.
It matches the tracker card title, so the card and executor session share one collision-free name.
`branch:` uses the same sprint basename as a namespace. Claim checks, branch creation, status, and
claim release all use that exact value — never a bare `sprint/NN-*` pattern.

`execution:` is declared once in `00-overview.md` and copied into every story. A story doc is a
prompt for a fresh agent; it must not require reading the overview to learn whether it may merge.

`frontend:` is true when any user-visible surface changes — not when `ownership.owns` happens to
contain component paths. A pure `lib/` change that alters what a page renders is a frontend story.
When unsure, set it true and name the surface.

`flow: direction` marks a story whose deliverable is an investigation dossier — planning input,
not product code. Direction stories are always `loop: full` and typically tier S. The executor
writes `dossier-NN.md` into the sprint directory (never `NN-dossier.md`: `sprint-status.sh`
enumerates `[0-9]*.md` files as stories, so that name surfaces a phantom story) and the dossier
commit is the story's only trailered commit. EXECUTION.md carries the full alternate terminal
path; the kickoff renders `Use skills: none` for direction stories.

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

- If verification contradicts a story premise, follow EXECUTION.md's divergence protocol: contained divergences proceed under a recorded amendment; cross-boundary ones offer the operator the handback that writes a REPLAN event. Never build around a broken premise.
- If two stories want the same files, update `00-overview.md` so they run serially or split ownership clearly.
- For artifact-returning work, mocked tests are not enough. Human inspection of the produced artifact is part of done.
