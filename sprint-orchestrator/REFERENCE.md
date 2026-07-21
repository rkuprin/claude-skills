# Sprint Orchestrator — Reference (mechanics)

Loaded on demand. The constitution (`SKILL.md`, beside this file) says why and when; this
file says exactly how. When they disagree, the constitution wins and this file is stale —
fix it.

## Trailer format

Every commit an executor makes for a story carries two trailers:

```
feat(reports): add date range presets

Story: 07
Sprint: 2026-07-07-report-delivery-sprint
```

`Sprint:` is the sprint directory's basename, verbatim — for `docs/sprints/2026-07-07-report-delivery-sprint`,
that's `2026-07-07-report-delivery-sprint`, not a shortened form or the tracker's sprint name.
`sprint-status.sh` matches it exactly against the directory it's given, so any other string makes
every story in that sprint read TODO forever. Both trailers, on the same commit: story numbers
restart every sprint, so a bare `Story: 07` match would make the next sprint's story 07 read
`DONE` on day one.

Read the current state with the `sprint-status.sh` helper that sits beside this file, from
the repo root. It is the same script reached via either agent's skills directory:

```bash
~/.claude/skills/sprint-orchestrator/sprint-status.sh docs/sprints/<sprint>   # Claude
~/.codex/skills/sprint-orchestrator/sprint-status.sh docs/sprints/<sprint>    # Codex
~/.agents/skills/sprint-orchestrator/sprint-status.sh docs/sprints/<sprint>   # Kimi
```

Stories are enumerated from files matching `[0-9]*.md`, skipping `00-*`. Suffixed numbers such as
`06b` are first-class.

Sprints planned before this convention have no trailers and their history is not rewritten. For
those, `00-overview.md` and `STORY-FEEDBACK.md` are the record; `sprint-status.sh` will
under-report them and that is expected.

## Event ledger

All events are immutable and append-only: Never edit an existing event block; corrections and
resolutions are appended as new events. Event IDs of all kinds carry the story number —
`rp-YYYYMMDD-NN-<n>`, `dr-YYYYMMDD-NN-<n>`, `dp-YYYYMMDD-NN-<n>` — so parallel writers cannot
collide on same-day IDs. Wave-scoped events — the pre-dispatch `rv-YYYYMMDD-w<wave>-<n>` and the
retro `rt-YYYYMMDD-w<wave>-<n>` — carry the wave number instead: they belong to no single story.
Events already recorded keep their old IDs.

REPLAN (executor handback; written under EXECUTION.md's divergence protocol):

    ## REPLAN — rp-YYYYMMDD-NN-<n> — Story NN
    - Premise as written: <quote from the story doc>
    - Contradicting evidence: <file/symbol/command anchors>
    - Blast radius: <affected stories, dependency edges, waves>
    - Recommendation: <one line>

DIRECTION (direction-story dossier landed):

    ## DIRECTION — dr-YYYYMMDD-NN-<n> — Story NN
    - Dossier: <path>
    - Recommendation: <one line>

DISPOSED (the wave gives up on a story — cut, deferred, or reassigned; wave accounting,
never DONE):

    ## DISPOSED — dp-YYYYMMDD-NN-<n> — Story NN
    - Outcome: cut | deferred | reassigned
    - Cleanup: <branch / worktree / PR disposition>
    - Reason: <one line>

REVIEW (pre-dispatch critic read, one per wave):

    ## REVIEW — rv-YYYYMMDD-w<wave>-<n> — pre-dispatch, wave <N>
    - Reviewer: <model + transport>
    - Stories: <NN list>
    - Findings: <one line each | none>
    - Advice: <one line>
    - Taken: <amended / cut / disagreed + why>
    - Report: <path to the reviewer's full output>

RETRO (one per driver family that executed in the wave, at wave conclusion):

    ## RETRO — rt-YYYYMMDD-w<wave>-<n> — wave <N> retro
    - Reviewer: <model + transport>
    - Driver family: claude/kimi | codex
    - Range: <base SHA>..<head SHA>
    - Findings: <one line each | none>
    - Advice: <one line each | none>
    - Report: <path to the reviewer's full output>

### The unresolved-event sweep

On ANY re-invocation of an existing sprint dir — wave boundary, handback, or a landed direction
story — FIRST sweep `STORY-FEEDBACK.md` for unresolved feedback events: every
`## REPLAN — rp-YYYYMMDD-NN-<n> — Story NN`,
`## DIRECTION — dr-YYYYMMDD-NN-<n> — Story NN`, `## DISPOSED — dp-YYYYMMDD-NN-<n> — Story NN`,
or `## RETRO — rt-YYYYMMDD-w<wave>-<n>` block with no matching `## RESOLUTION — <id>` block.
Re-verify each against current source truth; rewrite, cut, or split the affected story docs (for
a DIRECTION dossier: plan the follow-on stories or record why not; for a RETRO: weigh each
advice line into the next wave's plan, or record why it does not apply); then append the resolution as
its own immutable event — `## RESOLUTION — <id>` with a `- Resolution:` line.

Also check for unmerged `sprint-docs/*` branches or docs-only PRs — an event stuck behind an
unmerged PR is invisible to this sweep until it lands.

Sweep the mailbox in the same pass for terminal `concluded` outcomes no supervisor processed —
a prior session may have died between an executor's conclusion and its integration. Integrating
such a leftover comes BEFORE any planning, but never on inference: the session cannot know
whether the prior supervisor is really gone; only the operator knows. Ask interactively. The
operator's confirmation that the session ended satisfies the ownership-transfer precondition and
makes this session the successor supervisor for that conclusion; then integrate per the
constitution's supervision rules — verify the diff, evidence, and "Done means", merge per the
story's execution mode, run the DONE check. Without that confirmation, leave the conclusion
untouched and plan nothing that depends on it.

## Mailbox mechanics

The mailbox is transient mail in `~/.sprint-mail/<repo>/<sprint>/`, handled with `sprint-mail.sh`
(beside this file). It is never state — see the constitution.

The first action of every supervisor turn is a cursor sweep:
`sprint-mail.sh unread <sprint-dir> '*-question.md *-concluded.md'`
for the blocking kinds, then `sprint-mail.sh unread <sprint-dir> '*'` for the rest — read them,
then `sprint-mail.sh seen <sprint-dir> <files>`. That sweep against the durable read-cursor is
what makes mail never-lost: even if no wake fires, the next turn catches it.

Then park the turn with ONE command — `sprint-mail.sh supervise --harness <your harness>
<sprint-dir>` — and follow its output — the supervisor is always a main session, so each
harness waits in its own way:

- **Codex**: supervise idempotently arms the sweep wait
  (`arm --harness codex <sprint-dir> '*-question.md *-concluded.md' 1800`) and the Stop hook
  wakes you on new mail or timeout. Requires the one-time `install-codex-hook.sh`.
- **Claude**: same shape —
  `arm --harness claude <sprint-dir> '*-question.md *-concluded.md' 10800` (the idle-wait default
  under the installed hook's 10860s timeout; targeted reply waits keep 1800). Requires the
  one-time `install-claude-hook.sh`. Main sessions only: the hook is wired for `Stop`, never
  `SubagentStop`.
- **Kimi**: there is no Stop hook to arm — the wait is a recurring cron sweep, and supervise
  prints the exact task: CronList first, CronCreate only if no sweep task exists, then end the
  turn — with an active goal, mark it blocked (the blocked state IS the park: an active goal's
  continuation turns starve cron delivery, fires land only at idle); with no active goal, simply
  ending the turn is the park. The recurring task replaces the arm/re-arm loop — one task per
  wave, not one per wake; CronDelete it when the wave concludes. The Kimi session must run with
  a permission posture that lets the mailbox commands and cron management execute unattended
  (an auto permission mode or session-approved allow rules) — a sweep that stalls on an approval
  panel wakes no one.

Re-arm on each wake until the wave concludes — a spurious wake finds nothing unread, a missed
wake is caught by the next sweep. `sprint-status.sh` never reads the mailbox — nor the
read-cursor.

## In-session dispatch mechanics

The constitution sanctions in-session execution of `loop: direct` stories after recap approval.
The mechanics:

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
  afterwards is the integrate step's judgment.
- Transport is resolved at handoff time, never at plan time: when Claude capacity is tight, the
  same stories render as `codex exec` prints instead. Never subagent a `loop: full` story (they
  need an interactive session); `frontend: true` stories are a poor fit — their evidence path
  ends in Codex.app visual validation.
- Kickoffs fired as in-session subagents are rendered with the subagent topology
  (`wave-handoffs.sh <sprint-dir> <wave> --topology subagent`): a subagent never arms a
  blocking mailbox wait — the Stop hook never fires for it, on any harness — so its
  `Mailbox wait:` is the non-arming fallback. Only main sessions arm; in-session dispatch of
  a codex-transport story is `codex exec`, itself a main session. On Kimi the in-session
  transport is the Agent tool — same topology, same non-arming fallback. The operator's paste
  sheet renders with `--topology main-session` (plus `--target kimi` when the batch goes to
  Kimi sessions).

## The ladder

`tier:` grades the work's difficulty; `driver_hint:` grades its nature. Tier picks the row,
driver the column. A has one cell, so it binds the harness at plan time; S binds Claude-or-Kimi
(`kimi-k3` sits between fable and sol in capability and is fable's designed substitute when
Claude capacity is out — a handoff-time capacity swap, never a `driver_hint`); B and C stay
late-bound. Tiers are the operator's routing policy, not an empirical ordering.

| Tier | Claude (`--model`) | Codex (`-m`) | Kimi | Depth default |
|------|--------------------|--------------|------|---------------|
| S | `fable` | — | `kimi-k3` | high (xhigh only when capability-limited) |
| A | — | `gpt-5.6-sol` | — | xhigh |
| B | `opus` | `gpt-5.6-terra` | — | xhigh |
| C | `sonnet` | `gpt-5.6-luna` | — | high |

Depth scale, literal on both harnesses: `low | medium | high | xhigh | max`. Depth defaults are
operator policy for today's model generation — effort levels do not port across models; revisit
the defaults when a generation changes.

Orchestration shares the launch control with depth and implies xhigh: ultracode on Claude,
`model_reasoning_effort=ultra` on Codex. Sol and Terra support `ultra`; Luna does not — an
orchestrated C-tier codex story bumps to Terra.

## Story doc template

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

`00-overview.md` must include merge order, dependency edges, shared file hotspots, deferred-wave
stubs, cut items with reasons, and the path to `STORY-FEEDBACK.md`.

## Planner handoff template

Rendered by the outgoing supervisor at a wave boundary; pasted by the operator into a fresh
session:

    Sprint planning continues: <sprint-basename> — wave <N+1>

    Re-invoke /sprint-orchestrator on <literal sprint path>.
    Wave <N> outcome: <one line per story — merged / disposed / leftover>.
    Leftover in flight: <story NN and who holds it | none>.
    Unresolved events: <ids | none>.
    Wave retro: <rt-ids | none>.
    Mailbox: <literal mailbox path> — sweep it before planning.

    /goal Wave <N+1> planned, dispatched, and supervised to conclusion — every story
    merged or disposed — and the next planner handoff rendered.

The `/goal` targets the NEXT wave boundary — a goal that ends at dispatch would recreate the
plan-and-exit behavior this lifecycle replaces. `/goal` is native on all three harnesses, so
the handoff pastes cleanly into Claude, Codex, or Kimi.

### Sprint-terminal variant

When the sprint is complete — every story DONE or DISPOSED and no wave N+1 — render this form
instead. The re-invoke line is mandatory here too: the outgoing supervisor names the door,
even though only the operator and the fresh planner decide what walks through it.

    Sprint complete: <sprint-basename> — no wave <N+1>.

    Next: <next sprint per program order | none known>. Re-invoke /sprint-orchestrator with
    raw inputs when ready — a new sprint opens at the brief gate.
    Scope leads (to verify, not decisions): <pointers — dossier sections, overview stubs,
    cut items — that the next brief discussion should test against current source truth>.
    Wave <N> outcome: <one line per story — merged / disposed / leftover>.
    Leftover in flight: <story NN and who holds it | none>.
    Unresolved events: <ids | none>.
    Wave retro: <rt-ids | none>.
    Mailbox: <literal mailbox path> — reconciled.

    /goal <Next sprint> brief discussed and approved, wave 1 planned, dispatched, and
    supervised to conclusion — every story merged or disposed — and the next planner
    handoff rendered.

## Tracker binding

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
