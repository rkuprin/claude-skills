# Sprint supervisor: wave lifecycle, mailbox, and launch guidance — design

Date: 2026-07-14
Skills touched: `sprint-orchestrator`, `agent-handoff`
Source: operator voice memo, 2026-07-14; decisions settled interactively in the same session.

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

1. No prose anywhere in the skill body makes the running agent reason about its own model
   identity. Launch advice (Anthropic only — Fable preferred, else Opus) lives where the
   launching human reads it.
2. The orchestrator supervises a wave to conclusion: watches executors, answers them, verifies
   concluded stories, merges them in order, and disposes of problem stories at its own judgment
   — including finishing one inline when that is cheapest.
3. Planning continuity via fresh instances: at a wave boundary the sitting supervisor renders a
   paste-ready planner handoff for a new session of the same model, and stops. If a leftover
   holds it back but the next wave is unblocked, it hands off planning early and demotes itself.
4. A live executor↔supervisor channel — a watched filesystem mailbox — for evidence, questions,
   and conclusion pings, layered *on top of* the existing event protocol, never replacing it.
5. The orchestrator owns the interactivity call per story (`loop:`), and is written down as the
   user's single point of contact.
6. A first-run **sprint brief** gate: a colloquial, human-readable statement of what the sprint
   is and where its boundaries are, approved on screen before any story doc exists, persisted at
   the top of `00-overview.md`.

## Non-goals

- No change to story-state derivation, commit trailers, `sprint-status.sh`, `wave-handoffs.sh`,
  the tier ladder, per-story model routing (`tier:` × `driver_hint:` stays exactly as is),
  tracker binding, or the `loop: full` brainstorm gate semantics.
- No fourth `agent-handoff` mode: the planner handoff template lives in `sprint-orchestrator`.
- No new frontmatter keys.
- Mailbox carries no state: `sprint-status.sh` never reads it, and no story state is ever derived
  from it.

## Design

### 1. Model guidance moves to launch surfaces

Delete the entire "Run This on the Strongest Model" section from `sprint-orchestrator/SKILL.md`.
Nothing replaces it in the body — the running agent never names, checks, or apologizes for its
model. Sweep the two echoes: "fresh strongest-model session" (SKILL.md, Waves section) and
"fresh strongest-model planner session" (EXECUTION.md, direction stories) both become "a fresh
planner session".

The advice moves to two launch-time surfaces:

- `sprint-orchestrator/README.md` gains a short **Where to run it** section: sprint orchestration
  is judgment-heavy, shortcut-friendly work; run the planner on Anthropic models — Fable
  preferred, Opus fallback. Codex models execute stories well but follow process too literally to
  plan sprints. Story-level routing is unaffected — the planner still routes each story by the
  ladder.
- The SKILL.md frontmatter `description:` gains a trailing clause: "Best run on Claude (Fable,
  else Opus)." Launch advice only; phrased as a fact about where to launch, not an instruction to
  verify anything at runtime.

Lint: the "orchestrator: strongest-model gate" check flips polarity — fail if "Run This on the
Strongest Model" or the self-identification instruction ("name the model you are running as")
reappears in SKILL.md; new positive check that README carries the Where-to-run advice.

### 2. Sprint brief gate (first run only)

Plan Session gains a step 0, active only when the sprint is not yet defined (no existing sprint
directory or no `00-overview.md` in it):

- Run a short interactive discussion with the user: what this sprint is about, what is in, what
  is out, what done looks like.
- Print a **Sprint brief** on screen in colloquial, simple English. Iterate until the user
  approves it. Nothing else — no verification sweep, no story docs — happens before approval.
- The approved brief lands verbatim as the opening `## Sprint brief` section of
  `00-overview.md`.

Re-invocations on an existing sprint dir skip the gate but re-read the brief as the sprint's
scope boundary. The rest of the overview and the story docs stay dense and agent-facing — the
brief is the one human-facing artifact.

### 3. Supervisor lifecycle

The skill's identity changes from "plans and hands off, never implements, never declares done"
to **plan, dispatch, supervise, integrate**. The recap gate is unchanged and remains the plan
approval point.

1. **Plan** — as today: verify candidates, split stories, write docs, recap, user approves.
2. **Dispatch** — as today: render story handoffs; fire approved small `loop: direct` stories as
   subagents / `codex exec`. Additionally create the sprint's mailbox directory (§4).
3. **Supervise** — new: the session stays alive while the wave runs. It watches the mailbox and
   answers executor questions with the plan's authority, and polls story conclusions
   (`concluded` messages; PRs; `sprint-status.sh`; dossiers). Claude sessions may watch
   reactively (background monitor); `sprint-mail.sh wait` is the lowest-common-denominator poll.
4. **Integrate** — on each concluded story the supervisor verifies the result: diff, hand-back
   evidence, both trailers, the story's "Done means". Then:
   - verified good → under `stop-at-pr`, merge in `00-overview.md`'s merge order; under
     `autonomous` the executor already merged — the supervisor's check reviews what landed.
   - problems → the supervisor's judgment call, in rising order of cost: send feedback via
     mailbox `note` and let the executor fix; re-dispatch as a fresh handoff; **rescue inline**
     — finish the story itself when that is cheapest. Inline rescue follows EXECUTION.md like
     any executor: trailers on every commit, ownership bounds, single writer.
   - Execution-mode semantics: `autonomous` executors still merge themselves (unchanged);
     `stop-at-pr` now means the *executor* stops at the PR — the supervisor verifies and merges
     it, with the user present in the session. The "Integration Is Planned Here, Performed
     Elsewhere" section is rewritten to this split.
5. **Wave boundary** — when the wave's stories read DONE (or are disposed by explicit decision
   recorded in `STORY-FEEDBACK.md`), the supervisor does not plan the next wave in its own
   transcript. It renders a **planner handoff** — paste-ready, for a fresh session of the same
   model — and stops. Shape (exact wording at implementation, kept in SKILL.md):

   ```
   Sprint planning continues: <sprint-basename> — wave <N+1>

   Re-invoke /sprint-orchestrator on docs/sprints/<sprint>.
   Wave <N> outcome: <one line per story — merged / disposed / leftover>.
   Leftover in flight: <story NN and who holds it | none>.
   Unresolved events: <ids | none>.
   Mailbox: ~/.sprint-mail/<sprint>/ — sweep it before planning.

   /goal Wave <N+1> planned: brief re-read, events resolved, story docs written,
   recap approved, handoffs rendered.
   ```

6. **Early unblock** — if the supervisor is still nursing a leftover but nothing in wave N+1
   depends on it, it renders the planner handoff immediately and **demotes itself**: from that
   moment it touches only the leftover story's branch and the mailbox — never story docs,
   `00-overview.md`, or event resolutions. Executor-side events for the leftover (a REPLAN on
   handback) remain legal — it is now just an executor. The fresh instance is the sole planner.
   This preserves the one-planner-per-sprint-dir rule by succession instead of exclusion; the
   rule's wording changes to say a demoted supervisor no longer counts as a planner.

### 4. Mailbox

**Location**: `~/.sprint-mail/<sprint-dir-basename>/` — outside every worktree (same precedent
as `~/.handoffs` and `~/.sprint-evidence`), same machine, created by the supervisor at dispatch
(`mkdir -p`). Transient by contract: disposable after the sprint concludes; deleting it loses
nothing.

**Messages**: one file per message, append-only, never edited after writing.

- Name: `NN-SSS-<kind>.md` — story number, per-story sequence (one counter per story across all
  kinds, zero-padded), kind. A sorted listing is the story's chronology.
- Kinds, executor → supervisor:
  - `evidence` — findings that may affect other stories. Post and keep working; no reply
    expected.
  - `question` — a blocking question inside the story's scope. Post, then wait for a reply. An
    executor has at most one open question at a time.
  - `concluded` — the story reached its terminal artifact; body names the PR / dossier / branch
    and where the hand-back evidence lives.
- Kinds, supervisor → executor:
  - `reply` — answers the story's open question; body's first line names the question file.
  - `note` — unsolicited redirect. Executors check for new notes at each numbered EXECUTION.md
    step boundary and must have read all their story's notes before merge or PR.

**`sprint-mail.sh`** sits beside `sprint-status.sh`, bash + coreutils only:

- `post <sprint-dir> <NN> <kind> [<file>|-]` — writes the next-sequence message atomically
  (tmp + `mv`), prints the created path.
- `list <sprint-dir> [<NN>]` — chronological listing, optionally story-filtered.
- `wait <sprint-dir> <glob> [<timeout-seconds>]` — polls (~20s interval) until a matching file
  appears (prints its path, exit 0) or timeout (exit 1). Codex long-polls with this; Claude may
  use a reactive watch instead — `wait` is the floor, not the ceiling.

**Hard boundaries** (stated in both SKILL.md and EXECUTION.md, pinned by lint):

1. *The mailbox is never state.* `concluded` is a notification; DONE is still both trailers on a
   trunk-reachable commit. `sprint-status.sh` never reads the mailbox.
2. *The mailbox degrades to the existing protocol.* A `question` that times out falls back to
   Divergences-and-handback exactly as written today; anything plan-changing still lands as an
   immutable `STORY-FEEDBACK.md` event. Faster lane on top, never a replacement.

**EXECUTION.md changes**:

- New short **Mailbox** section: location, kinds, the step-boundary check discipline, the
  read-notes-before-merge/PR rule.
- Cross-boundary divergence on a non-interactive transport changes from "hand back without
  asking" to: post the evidence as a `question`, `wait` on a reply; the supervisor may answer
  continue (recorded amendment) or instruct handback; timeout → hand back exactly as today.
- Step 8 (hand off) additionally posts `concluded`.
- The three interrupts remain the only stop conditions; posting to the mailbox is not stopping.

### 5. Point of contact and the `loop:` call

- `loop:` guidance drops "ask the user when unsure" — the orchestrator owns the call. The recap
  gate still shows every story's `loop:` before dispatch, so the user can veto there.
- A short **Point of contact** principle lands near the top of SKILL.md: the user talks to the
  orchestrator; executors talk to it through the mailbox; the user enters a story session only
  when the plan routed an interactive (`loop: full`) story there.

### 6. Lint and tests

- Flip "orchestrator: strongest-model gate" to absence checks; add README Where-to-run check
  (§1).
- New pins: sprint-brief gate wording; supervisor merge rule per execution mode; inline-rescue
  bound by EXECUTION.md; demotion rule; mailbox-never-state; question-timeout fallback;
  planner-handoff rendered at wave boundary; "fresh planner session" wording (no
  "strongest-model" remnant).
- `test/test-sprint-mail.sh`: post sequencing (per-story counter, zero-padding, atomicity —
  no partial file visible), list ordering and filtering, wait success and timeout exit codes.
- Existing suites must stay green: `test/lint-skills.sh`, `test-sprint-status.sh`,
  `test-wave-handoffs.sh`.

## Files touched

| File | Change |
|---|---|
| `sprint-orchestrator/SKILL.md` | model section deleted; description clause; brief gate; supervisor lifecycle; mailbox (supervisor side); point of contact; planner-handoff template |
| `sprint-orchestrator/README.md` | Where to run it; lifecycle description update |
| `sprint-orchestrator/sprint-mail.sh` | new |
| `sprint-orchestrator/test/test-sprint-mail.sh` | new |
| `agent-handoff/EXECUTION.md` | Mailbox section; softened non-interactive divergence; `concluded` post in step 8; wording sweep |
| `agent-handoff/SKILL.md` | at most one mailbox line in the story kickoff template |
| `test/lint-skills.sh` | flipped and new pins, same commit as the prose they pin |
