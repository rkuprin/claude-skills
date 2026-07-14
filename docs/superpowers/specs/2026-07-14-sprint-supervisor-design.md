# Sprint supervisor: wave lifecycle, mailbox, and launch guidance — design

Date: 2026-07-14
Skills touched: `sprint-orchestrator`, `agent-handoff`
Source: operator voice memo, 2026-07-14; decisions settled interactively in the same session.
Codex review: 2026-07-14 (sol/xhigh) — findings folded in: ownership-transfer protocol,
sender-split mail sequencing with deterministic replies, terminal outcomes on every exit,
autonomous merge-order constraint, trailer-preserving merge + post-merge DONE check, DISPOSED
events, wave-targeted planner-handoff goal + demotion cutover, three-case brief predicate,
README-only launch advice, widened file/lint/test scope.

## Problem

Five gaps, one root: the orchestrator plans well but cannot carry a sprint.

1. **The model self-gate misfires.** "Run This on the Strongest Model" asks the running agent to
   name its own model. Codex models take the instruction literally and stop ("I'm not Sol, I'm
   just ChatGPT"). And the premise is wrong anyway: sprint orchestration is judgment-heavy,
   shortcut-friendly work that OpenAI models are poor at regardless of tier — the advice belongs
   to the human choosing where to launch, not to the agent that already launched.
2. **Nothing concludes a wave.** Stories end at PRs and dossiers, then everything waits for the
   user to notice, merge, and re-invoke the planner. The one session that has full context — the
   planner — exits right after dispatch.
3. **Wave re-entry drags a poisoned context.** If the planner *did* stay alive through a wave,
   planning wave N+1 in the same transcript wastes tokens and focus on supervision leftovers.
   There is no fresh-instance handoff for planning continuity.
4. **Mid-story evidence has exactly one shape: die.** An executor that finds evidence affecting
   other stories, or has one blocking question, must stop, publish a REPLAN event, and hand back
   — even when a one-line answer from the planner would have kept the story alive. There is no
   live channel between executors and the planner.
5. **The sprint starts without a human-readable definition.** First invocation goes straight to
   story docs. There is no checkpoint where the sprint's intent and boundaries are written in
   plain English and approved before stories exist.

## Goals

1. No prose anywhere in the skill body — or in harness-visible metadata — makes the running
   agent reason about its own model identity. Launch advice (Anthropic only — Fable preferred,
   else Opus) lives in READMEs, which only the launching human reads.
2. The orchestrator supervises a wave to conclusion: watches executors, answers them, verifies
   concluded stories, merges them in order, and disposes of problem stories at its own judgment
   — including finishing one inline when that is cheapest.
3. Planning continuity via fresh instances: at a wave boundary the sitting supervisor renders a
   paste-ready planner handoff for a new session of the same model, and stops. If a leftover
   holds it back but the next wave is unblocked, it hands off planning early and demotes itself.
4. A live executor↔supervisor channel — a watched filesystem mailbox — for evidence, questions,
   and terminal outcomes, layered *on top of* the existing event protocol, never replacing it.
5. The orchestrator owns the interactivity call per story (`loop:`), and is written down as the
   user's single point of contact.
6. A first-run **sprint brief** gate: a colloquial, human-readable statement of what the sprint
   is and where its boundaries are, approved on screen before any story doc exists, persisted at
   the top of `00-overview.md`.

## Non-goals

- No change to story-state derivation, commit trailers, `sprint-status.sh`, the tier ladder,
  per-story model routing (`tier:` × `driver_hint:` stays exactly as is), tracker binding, or
  the `loop: full` brainstorm gate semantics.
- No fourth `agent-handoff` mode: takeover kickoffs are story-execution renders carrying a
  resume grant; the planner handoff template lives in `sprint-orchestrator`.
- No new frontmatter keys.
- Mailbox carries no state: `sprint-status.sh` never reads it, and no story state is ever
  derived from it.

## Design

### 1. Model guidance moves to launch surfaces

Delete the entire "Run This on the Strongest Model" section from `sprint-orchestrator/SKILL.md`.
Nothing replaces it in the body — the running agent never names, checks, or apologizes for its
model. Sweep the two echoes: "fresh strongest-model session" (SKILL.md, Waves section) and
"fresh strongest-model planner session" (EXECUTION.md, direction stories) both become "a fresh
planner session".

The advice moves to README surfaces **only** — never to frontmatter. The `description:` field is
harness invocation metadata fed to the running agent; launch advice there could re-trigger the
exact self-disqualification this change removes:

- `sprint-orchestrator/README.md` gains a short **Where to run it** section: sprint orchestration
  is judgment-heavy, shortcut-friendly work; run the planner on Anthropic models — Fable
  preferred, Opus fallback. Codex models execute stories well but follow process too literally to
  plan sprints. Story-level routing is unaffected — the planner still routes each story by the
  ladder.
- The root `README.md` table row for `sprint-orchestrator` carries the same one-line advice.
- `sprint-orchestrator/agents/openai.yaml` and the SKILL.md `description:` are updated to the
  supervisor role wording (plan, dispatch, supervise, integrate) — role description only, no
  model advice in either.

Lint: the "orchestrator: strongest-model gate" check flips polarity — fail if "Run This on the
Strongest Model", "name the model you are running as", or any stop-and-relaunch self-check
reappears in SKILL.md or its frontmatter; new positive check that README carries the
Where-to-run advice.

### 2. Sprint brief gate — three entry cases

Plan Session gains a step 0 whose behavior depends on what exists:

- **Undefined sprint** — no sprint directory, or one containing neither story docs nor
  `00-overview.md`: run a short interactive discussion with the user (what this sprint is about,
  what is in, what is out, what done looks like), print a **Sprint brief** on screen in
  colloquial, simple English, and iterate until the user approves. Nothing else — no
  verification sweep, no story docs, no writes — happens before approval. The approved brief
  lands verbatim as the opening `## Sprint brief` section of `00-overview.md`.
- **Legacy sprint** — `00-overview.md` exists without a `## Sprint brief` section: skip the
  gate; do not force a backfill. The overview as written is the scope boundary. Backfill only if
  the user asks.
- **Partial or damaged sprint** — story docs or `STORY-FEEDBACK.md` exist but `00-overview.md`
  does not: stop and ask the user how to recover. Never run first-run creation over an existing
  partial directory.

Re-invocations on a defined sprint re-read the brief (when present) as the sprint's scope
boundary. The rest of the overview and the story docs stay dense and agent-facing — the brief is
the one human-facing artifact.

### 3. Supervisor lifecycle

The skill's identity changes from "plans and hands off, never implements, never declares done"
to **plan, dispatch, supervise, integrate**. The recap gate is unchanged and remains the plan
approval point.

1. **Plan** — as today: verify candidates, split stories, write docs, recap, user approves.
2. **Dispatch** — render story handoffs; fire approved small `loop: direct` stories as
   subagents / `codex exec`; create the sprint's mailbox directory (§4). Parallel dispatch
   constraint: under `autonomous`, executors merge themselves, so the supervisor cannot enforce
   merge order — fire in parallel only stories that are BOTH ownership-disjoint AND
   merge-order-independent. When merge order matters, use `stop-at-pr` (the supervisor merges in
   order) or dispatch serially. `wave-handoffs.sh`'s unconditional "These run in parallel"
   sentence becomes conditional on this.
3. **Supervise** — new: the session stays alive while the wave runs. It watches the mailbox and
   answers executor questions with the plan's authority, and reacts to terminal outcomes
   (`concluded` messages; PRs; `sprint-status.sh`; dossiers). Claude sessions may watch
   reactively (background monitor); `sprint-mail.sh wait` is the lowest-common-denominator poll.
4. **Integrate** — on each terminal outcome the supervisor verifies the result: diff, hand-back
   evidence, the story's "Done means". Then:
   - `stop-at-pr`, verified good → the supervisor merges, in `00-overview.md`'s merge order.
     Merge mechanics: the method must preserve trailers — merge commit or rebase; squash only if
     the squash commit message itself carries both trailers. Conflicts: rebase once, retry once,
     else stop and report (same rule as EXECUTION.md step 6). The done-check is
     `sprint-status.sh` reporting `DONE` **after** the merge — inspecting trailers on the feature
     branch beforehand is not the check. Then deploy and verify prod per the project's
     convention (AGENTS.md), under EXECUTION.md's never-leave-prod-broken rule; fire the tracker
     `card.done` intent only after the DONE check passes.
   - `autonomous` → the executor already merged; the supervisor's check reviews what landed,
     including the same post-merge `sprint-status.sh` DONE check. A story that landed without
     trailers is a defect: dispose or re-dispatch a fix under ownership transfer.
   - problems → the supervisor's judgment call, in rising order of cost: send feedback via
     mailbox `note` (only while the story has not concluded); re-dispatch under ownership
     transfer; **rescue inline** — take the story over itself under ownership transfer and
     finish it, following EXECUTION.md like any executor: trailers on every commit, ownership
     bounds, single writer.
5. **Wave boundary** — the wave concludes when every story is `DONE` or carries a DISPOSED
   event (below). The supervisor does not plan the next wave in its own transcript. It renders a
   **planner handoff** — paste-ready, for a fresh session of the same model — and stops. Shape
   (exact wording at implementation, kept in SKILL.md):

   ```
   Sprint planning continues: <sprint-basename> — wave <N+1>

   Re-invoke /sprint-orchestrator on <literal sprint path in this repo>.
   Wave <N> outcome: <one line per story — merged / disposed / leftover>.
   Leftover in flight: <story NN and who holds it | none>.
   Unresolved events: <ids | none>.
   Mailbox: <literal mailbox path> — sweep it before planning.

   /goal Wave <N+1> planned, dispatched, and supervised to conclusion — every story
   merged or disposed — and the next planner handoff rendered.
   ```

   The `/goal` targets the NEXT wave boundary, not "handoffs rendered" — a goal that ends at
   dispatch would recreate the plan-and-exit behavior this design removes. The handoff never
   asks the receiving session to identify its model.
6. **Early unblock** — if the supervisor is still nursing a leftover but nothing in wave N+1
   depends on it, it renders the planner handoff immediately and **demotes itself**. Cutover is
   sharp: from the moment the handoff is rendered, the old session answers no mailbox messages
   and writes no planning files (story docs, `00-overview.md`, event resolutions) — it acts
   solely as its leftover story's executor, posting executor kinds and appending executor-side
   events (a REPLAN on handback) as any executor would. The fresh instance is the sole planner
   and answers everything. This preserves the one-planner-per-sprint-dir rule by succession; the
   rule's wording changes to say a demoted supervisor no longer counts as a planner.

### Ownership transfer

Re-dispatch, inline rescue, and demotion succession all require operating on a branch that
already exists — which the preflight ("designated branch exists → the story is taken → STOP")
correctly forbids for ordinary kickoffs. Takeover is legal only through this protocol:

- **Precondition**: the current owner is finished — it posted a terminal `concluded` outcome, or
  its transport is confirmed dead (subagent exited; the user closed the session). Never take
  over a live executor.
- **Transfer record**: the supervisor names the branch, the worktree path (if any), the HEAD
  SHA, and what remains to be done.
- **Resume grant**: the successor's kickoff is a story-execution render carrying an explicit
  grant — "resume designated branch `<branch>` at `<sha>`" — with the transfer record. The
  grant is the ONLY thing that overrides the branch-exists preflight refusal; a kickoff without
  one still refuses. Inline rescue states the same grant in-session before its first commit.
- **Single writer**: the grant names exactly one successor; at most one authorized owner exists
  at any moment.

### Disposal is an event

"Disposed" must be durable and legible to the next planner — a disposed story with commits still
reads `DOING` in git-derived status, and nothing else says that is intentional. Disposal is
recorded as an immutable `STORY-FEEDBACK.md` event, same discipline as REPLAN/DIRECTION:

```
## DISPOSED — dp-YYYYMMDD-NN-<n> — Story NN
- Outcome: cut | deferred | reassigned
- Cleanup: <branch / worktree / PR disposition>
- Reason: <one line>
```

DISPOSED is wave accounting, never `DONE`: `sprint-status.sh` keeps reporting git truth, and the
next planner treats a DISPOSED story as settled intent, not unfinished work. Event IDs of all
kinds gain the story number segment going forward — `rp-YYYYMMDD-NN-<n>`, `dr-YYYYMMDD-NN-<n>`,
`dp-YYYYMMDD-NN-<n>` — so parallel writers cannot collide on same-day IDs. Existing recorded
events keep their old IDs (events are immutable).

### Rules rewritten, not left contradicting

Three existing `sprint-orchestrator/SKILL.md` rules collide with the new lifecycle and are
rewritten explicitly:

- "Mutate only sprint planning files and tracker sink calls" → the supervisor also merges story
  branches per execution mode, deploys at integration, and may rescue under ownership transfer.
- "This skill's only sanctioned in-session execution" (direct stories) → inline rescue joins as
  the second sanctioned execution, bounded by ownership transfer and EXECUTION.md.
- "First failure stops the fleet" → applies to the dispatch batch (no automatic retries
  mid-batch); after the batch, disposal / re-dispatch / rescue decisions at the integrate step
  are the supervisor's judgment.

### 4. Mailbox

**Location**: `~/.sprint-mail/<repo-basename>/<sprint-dir-basename>/` — outside every worktree
(same precedent as `~/.handoffs` and `~/.sprint-evidence`), same machine, created by the
supervisor at dispatch (`mkdir -p`). The repo segment keeps identically-named sprints in
different repos apart. Transient by contract: disposable after the sprint concludes; deleting it
loses nothing. One mailbox serves the whole sprint across waves — no epoch needed, because waits
target deterministic filenames (below), so old files cannot satisfy new waits.

**Messages**: one file per message, append-only, never edited after writing. Name:
`NN-SSS-<kind>.md` — story number, sequence, kind.

Sequencing is **split by sender**, which removes allocation races without locking (this machine
is bash 3.2, no `flock`):

- The executor owns its story's counter for `evidence`, `question`, and `concluded`.
- A `reply` reuses the sequence of the question it answers — `NN-SSS-reply.md` is deterministic,
  so the executor waits on one exact filename; correlation and stale-match problems disappear.
  An executor has at most one open question at a time.
- A `note` uses a supervisor-owned per-story counter. Same-name collisions are impossible: each
  counter has a single writer, and the kind is part of the filename.
- Filename order is chronological per sender only; `list` orders globally by mtime.

Kinds:

- executor → supervisor: `evidence` (findings that may affect other stories — post and keep
  working; no reply expected), `question` (blocking, inside the story's scope — post, then wait
  for the matching reply), `concluded` (terminal — see below).
- supervisor → executor: `reply` (answers the open question), `note` (unsolicited redirect,
  legal only while the story has not concluded). Executors check for new notes at each numbered
  EXECUTION.md step boundary and must have read all their story's notes before merge or PR.

**Terminal outcomes**: every exit path posts `concluded`, whose first line is
`outcome: merged | pr-ready | handback | blocked | failed | dossier`, and whose body names the
terminal artifact (PR / dossier / branch) and where hand-back evidence lives. After posting it
the executor is gone: post-conclusion fixes go through ownership transfer and re-dispatch, never
through notes to a session that no longer exists.

**`sprint-mail.sh`** sits beside `sprint-status.sh`, bash 3.2 + coreutils only:

- `post <sprint-dir> <NN> <kind> [<file>|-]` — writes the next-sequence message atomically
  (tmp + `mv`), prints the created path. Rejects unknown kinds and non-numeric story values.
- `list <sprint-dir> [<NN>]` — mtime-ordered listing, optionally story-filtered.
- `wait <sprint-dir> <name-or-glob> [<timeout-seconds>]` — polls (~20s interval) until a match
  appears (prints its path, exit 0) or timeout (exit 1). Default timeout 1800s. Codex long-polls
  with this; Claude may use a reactive watch instead — `wait` is the floor, not the ceiling.

A reply that arrives after its question timed out is **void**: the executor has already fallen
back to the handback protocol, and the supervisor learns that from the story's terminal outcome.

**Hard boundaries** (stated in both SKILL.md and EXECUTION.md, pinned by lint):

1. *The mailbox is never state.* `concluded` is a notification; DONE is still both trailers on a
   trunk-reachable commit. `sprint-status.sh` never reads the mailbox.
2. *The mailbox degrades to the existing protocol.* A `question` that times out falls back to
   Divergences-and-handback exactly as written today; anything plan-changing still lands as an
   immutable `STORY-FEEDBACK.md` event. Faster lane on top, never a replacement.

**EXECUTION.md changes**:

- New short **Mailbox** section: location, kinds, sequencing rules, the step-boundary check
  discipline, the read-notes-before-merge/PR rule.
- Cross-boundary divergence on a non-interactive transport changes from "hand back without
  asking" to: post the evidence as a `question`, `wait` on the deterministic reply; the
  supervisor may answer continue (recorded amendment) or instruct handback; timeout → hand back
  exactly as today.
- Terminal outcome posting is woven into EVERY exit: step 8 (`merged` / `pr-ready`), handback
  step 4 (`handback`), the direction-story terminal path (`dossier`), interrupt 2 (`failed`),
  interrupt 3 (`blocked`).
- The three interrupts remain the only stop conditions; posting to the mailbox is not stopping.

### 5. Point of contact and the `loop:` call

- `loop:` guidance drops "ask the user when unsure" — the orchestrator owns the call. The recap
  gate still shows every story's `loop:` before dispatch, so the user can veto there.
- A short **Point of contact** principle lands near the top of SKILL.md: the user talks to the
  orchestrator; executors talk to it through the mailbox; the user enters a story session only
  when the plan routed an interactive (`loop: full`) story there.

### 6. Lint and tests

- Flip "orchestrator: strongest-model gate" to absence checks; add the README Where-to-run
  check; pin the absence of launch advice in frontmatter (§1).
- Rescope the blunt "no unconditional 'do not merge'" absence check: scoped executor phrasing
  ("stop-at-pr executors do not merge") must pass; an unconditional planner-wide ban must still
  fail.
- New pins: three-case brief predicate; supervisor merge rule per execution mode;
  trailer-preserving merge + post-merge `sprint-status.sh` DONE check; autonomous merge-order
  dispatch constraint; ownership-transfer resume grant (and that ordinary kickoffs still refuse
  existing branches); terminal-outcome rule (every exit posts `concluded` with an outcome);
  DISPOSED event heading; planner-handoff `/goal` targeting the next wave boundary; demotion
  cutover; mailbox-never-state; question-timeout fallback; "fresh planner session" wording (no
  "strongest-model" remnant).
- `test/test-sprint-mail.sh`: per-sender sequencing and zero-padding; concurrent executor +
  supervisor posts to one story with no loss; deterministic reply wait (ignores older replies);
  wait timeout exit code; late reply void (documented behavior: wait already returned 1);
  malformed kind/story rejection; mailbox reuse across waves; atomicity (no partial file
  visible).
- `test-wave-handoffs.sh` additions: mailbox line rendered; conditional parallel wording; no
  resume grant in ordinary kickoffs.
- Existing suites must stay green: `test/lint-skills.sh`, `test-sprint-status.sh`,
  `test-wave-handoffs.sh`.

## Files touched

| File | Change |
|---|---|
| `sprint-orchestrator/SKILL.md` | model section deleted; supervisor description wording; brief gate (three cases); supervisor lifecycle; ownership transfer; DISPOSED events; rewritten rules; mailbox (supervisor side); point of contact; planner-handoff template |
| `sprint-orchestrator/README.md` | Where to run it; lifecycle description update |
| `sprint-orchestrator/agents/openai.yaml` | supervisor role wording (no model advice) |
| `sprint-orchestrator/sprint-mail.sh` | new |
| `sprint-orchestrator/test/test-sprint-mail.sh` | new |
| `sprint-orchestrator/wave-handoffs.sh` | mailbox line; conditional parallel wording; kickoff parity with agent-handoff template |
| `sprint-orchestrator/test/test-wave-handoffs.sh` | new checks per §6 |
| `agent-handoff/SKILL.md` | mailbox line in the kickoff template; resume-grant render rule for takeover kickoffs |
| `agent-handoff/EXECUTION.md` | Mailbox section; terminal outcomes on every exit; softened non-interactive divergence; resume-grant preflight exception; event-ID story segment; wording sweep |
| `agent-handoff/README.md` | supervisor-era description sweep |
| `README.md` (root) | table row advice + supervisor wording |
| `test/lint-skills.sh` | flipped, rescoped, and new pins, same commit as the prose they pin |
