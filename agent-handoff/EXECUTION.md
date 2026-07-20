# Execution contract — one sprint story, end to end

You are executing ONE planned story. Your kickoff prompt names the story doc, the sprint, your
EXECUTION MODE, and your `/goal`. This contract is the how. Product scope and decisions in the
story doc and `00-overview.md` are settled by default; the operator may amend them live at the
brainstorm gate, and every amendment is recorded in STORY-FEEDBACK.md. If you find a wrong
premise, an internal contradiction, or a genuine product ambiguity, follow "Divergences and
handback" below — never build around a broken premise.

## 0. Preflight

- `git fetch origin`
- If this story's designated branch — the story doc's exact `branch:` value — already exists on
  any ref, the story is taken. STOP and report; never co-opt someone else's branch. Story numbers
  restart every sprint, so a bare `sprint/{NN}-*` match false-positives on previous sprints.
  Sole exception: your kickoff carries a resume grant naming this exact branch and a HEAD SHA.
  Verify the branch's HEAD matches the grant (mismatch → STOP and report), reuse the branch, and
  continue from the transfer record instead of branching fresh.
- `git switch -c "{BRANCH}" origin/main` — use the story doc's exact `branch:` value. NEVER run `git checkout main`: trunk is checked
  out in another worktree and the command fails. Trunk is `origin/main`; if the project uses
  another trunk, `00-overview.md` says so. (`sprint-status.sh` honors `SPRINT_TRUNK`; that
  asymmetry is known and not yours to fix.) Until your first story commit this branch is a
  **claim**: it carries no story commits and exists to signal DOING to other sessions.
- Confirm this worktree is linked to the real deploy project before any deploy (see AGENTS.md).

## 1. Investigate — read-only

- Do the story doc's "Start by verifying" first. Reproduce the bug / establish the baseline
  BEFORE changing anything, capturing the "before" screenshots while you are there. Restate
  In/Out of scope.

## 2. Brainstorm gate — `loop: full` only

Your kickoff prompt's planning-depth line says whether this phase applies; `loop: direct`
stories skip to step 3.

- Your counterparty at this gate is the sprint orchestrator, reached through a mailbox
  `question` per the Mailbox section — the default and first resort for every open decision,
  every spec or design review, and every approval. Route them all there; the human at your
  terminal is not your counterparty. The operator is your counterparty only when the plan put
  them in the loop for an interactive story AND your kickoff names them as present — a dispatched
  kickoff (one that names a Mailbox and a Mailbox wait line) never does, and the planning-depth
  line's "brainstorm phase with the operator first" describes the phase, not who answers.
  Never demand an in-thread approval ("reply approved", "reply 'approve spec'") from a human who
  is not in this session — route it to the orchestrator instead; no reply within the wait is a
  handback, not permission to keep waiting.
- What the story doc, `00-overview.md`, and your kickoff already settled is approved. Do not
  re-open it as a fresh approval gate: inventing a spec sign-off the plan never asked for, then
  blocking on it, is the exact stall this gate exists to prevent.
- Present the investigation findings to your counterparty: what you verified, what surprised
  you, and 2-3 candidate approaches with trade-offs and your recommendation.
- Decisions in the story doc are settled by default; the counterparty may amend them here.
  Record every amendment in STORY-FEEDBACK.md — the append rides your story commits.
- If findings diverge from the story doc, apply "Divergences and handback" below before writing
  any code.
- This gate is interactive by design. The single-late-checkpoint rule (and the "progress pings"
  mistake below) applies only AFTER the counterparty says proceed.

## 3. Plan

- `loop: full`: write the spec and the plan as files on the story branch, reflecting what the
  brainstorm settled.
- `loop: direct`: the story is fully defined — write a short TDD plan and go.

## 4. Implement

- TDD: failing test first.
- Stay strictly inside `ownership.owns`; never touch `do_not_touch`.
- Every commit you make for this story carries the trailer block from your kickoff prompt:

      Story: {NN}
      Sprint: {SPRINT}

  This is the only record that the story landed. A commit without both is invisible to sprint
  status.

- Orchestration (ultracode / `ultra`) never waives this contract: every commit — including
  commits produced by subagents or workflow stages — carries both trailers, `ownership.owns` /
  `do_not_touch` bind all subagents, and there is a single writer per file at any moment.

## 5. Validate locally

Tests + typecheck; drive the story doc's Browser Verification locally; capture the "after"
screenshots; open any produced artifact. Fix until green.

## 6. Merge & deploy — AUTONOMOUS mode only

Under STOP AT PR: open a PR, do not merge, do not deploy. Trailers still go on every commit; `DONE`
flips when the human merges. Skip to step 8.

- Gate: story tests + typecheck + a production build all pass, and the story's commits carry BOTH
  trailers.
- Merge into trunk in `00-overview.md`'s merge order; ensure trunk is green.
- If the push is rejected because another session landed first: `git pull --rebase` and retry ONCE.
  Rejected again → STOP and report. Never force-push.
- Deploy with the project's deploy command (AGENTS.md).

## 7. Verify on prod — AUTONOMOUS mode only

- Drive the Browser Verification against the LIVE URL with a real test account; capture prod
  screenshots.
- Defect → fix, re-gate, redeploy, re-check. If prod breaks and it is not a fast fix → roll back
  (or revert the merge) and report. Never leave prod broken.

## 8. Hand off

- Append findings to STORY-FEEDBACK.md, including any surface you had to add to `surfaces:`.
- Produce the "How to test this yourself" section: what changed · live URL + role/account · exact
  steps, expected vs observed · test data/accounts · evidence (inline screenshots + provenance) ·
  risk + how to roll back · checks run (commands + results, build, deploy id) · open questions.
- Tracker: fire the `card.done` intent per the project's tracker binding. Where attachments are
  impossible (e.g. the Asana V2 MCP), the written hand-back reaches the card via `add_comment`.
- State branch, files, tests + results, deploy id.
- Post the terminal outcome: `concluded` with `outcome: merged` (AUTONOMOUS) or
  `outcome: pr-ready` (STOP AT PR), naming the PR or branch and the evidence location.

## Mailbox

Transient mail between you and the sprint supervisor lives at
`~/.sprint-mail/<repo-basename>/<sprint-basename>/` — your kickoff prompt names the literal
path. Post and read with `sprint-mail.sh` (beside `sprint-status.sh` in the
sprint-orchestrator skill directory). Files are `NN-SSS-<kind>.md`, append-only, never edited.

- `evidence` — findings that may affect other stories. Post and keep working; no reply comes.
- `question` — a blocking question inside this story's scope. Post it, then wait on the reply,
  which reuses your question's sequence — the exact filename `{NN}-{SSS}-reply.md`.
  One open question at a time. A reply that arrives after your wait ended is void — by then
  you are on the fallback path. How you wait is transport-specific — your kickoff's
  `Mailbox wait:` line carries the form already resolved for your transport; when it is
  absent, pick your branch here:
  - Codex (Desktop or exec) with the sprint Stop hook installed:
    `sprint-mail.sh arm --harness codex <sprint-dir> {NN}-{SSS}-reply.md 1800`, then END
    YOUR TURN with a one-line status. The armed hook holds the turn and wakes you when the
    reply lands or the wait times out. Arming and ending the turn IS the wait — never poll,
    never run `wait` under `nohup`/`&`/tmux, never hand-poll in later commands.
  - Claude, MAIN session only, with the sprint Stop hook installed (install-claude-hook.sh):
    `sprint-mail.sh arm --harness claude <sprint-dir> {NN}-{SSS}-reply.md 1800`, then END
    YOUR TURN with a one-line status — same semantics as the Codex form.
  - Kimi (interactive session): Kimi has no Stop-hook wait — `arm` refuses it. Post your
    question and note the post time, then CronCreate a recurring check (every 3 minutes)
    whose prompt reads: "Sprint mailbox wait for {NN}-{SSS}-reply.md: run
    `~/.agents/skills/sprint-orchestrator/sprint-mail.sh unread <sprint-dir> '{NN}-{SSS}-reply.md'`
    from the worktree. If the reply landed at or before <deadline — a literal epoch, post
    time + 1800s; compare against `stat -f %m` of the reply file>: read it, mark it seen,
    delete this cron task with CronDelete, then resume the waiter's goal with UpdateGoal
    active and continue. If it landed later, or the deadline has passed with no reply:
    delete this cron task and take the no-reply fallback. Otherwise end the turn — the goal
    stays blocked." Then mark your goal blocked — the designed wait protocol, not a failure:
    an active goal's continuation turns starve cron delivery, so the blocked state IS the
    park — and END YOUR TURN. The cron nudge wakes you — never poll, never run `wait` under
    `nohup`/`&`/tmux, never hand-poll in later commands.
  - An in-session subagent (any harness — the Stop hook never fires for a subagent, so
    you cannot end your turn and be woken), or neither hook available: do not pretend to
    wait — treat it as no reply and take the fallback path now.
- `concluded` — posted once, on EVERY exit (below).
- Sweep new `note` messages at each numbered step boundary:
  `sprint-mail.sh unread <sprint-dir> '{NN}-*-note.md'`, read them, then
  `sprint-mail.sh seen <sprint-dir> <files>` — the read-cursor means a note is never missed nor
  re-read. Read all of your story's notes before merge or PR.

The mailbox is never state: DONE is still both trailers on a trunk-reachable commit, and
`sprint-status.sh` never reads the mailbox — nor the read-cursor. When nobody answers,
the mailbox degrades to the handback protocol — nothing new to learn, just faster when it works.

**Terminal outcome.** Every exit posts `concluded`, first line
`outcome: <merged | pr-ready | handback | blocked | failed | dossier>`, body naming the
terminal artifact (PR / dossier / branch) and where the hand-back evidence lives. After posting
it you are done — never resume the story afterwards. Fixes arrive as a fresh kickoff under an
ownership transfer, not as notes to a session that no longer exists. A preflight refusal (taken branch, or a resume-grant SHA mismatch) reports via its transport and posts nothing — you never owned the story, and its mailbox counters belong to whoever does.

## Divergences and handback

When investigation or brainstorm findings diverge from the story doc, grade the blast radius:

- **Contained** — the divergence stays inside this story's scope and ownership (the bug is in Y,
  not X; same shape of fix). Operator present in this session: settle it with them, record it in
  STORY-FEEDBACK.md, proceed. Otherwise: proceed under a recorded amendment without stopping.
- **Cross-boundary** — the divergence invalidates the premise, reshapes other stories, changes
  merge order or waves, or reveals the story should not exist. Operator present in this session:
  present the premise, the contradicting evidence, and the blast radius, then ask them:
  **hand back to sprint-orchestrator now, or continue?** Otherwise: post the
  premise, evidence, and blast radius as a mailbox `question` and wait on the reply per the
  Mailbox section; the supervisor may answer continue (record the amendment and proceed) or
  instruct handback. No reply within the wait → hand back exactly as below.

On hand back:

1. Append a REPLAN event to STORY-FEEDBACK.md. Events are immutable, carry an id, and are never
   edited afterwards:

       ## REPLAN — rp-YYYYMMDD-{NN}-<n> — Story {NN}
       - Premise as written: <quote from the story doc>
       - Contradicting evidence: <file/symbol/command anchors>
       - Blast radius: <affected stories, dependency edges, waves>
       - Recommendation: <one line>

2. Publish it: commit the append as a docs-only commit with NO `Story:`/`Sprint:` trailers — a
   trailered commit reaching trunk would flip this story to DONE — on a
   `sprint-docs/rp-YYYYMMDD-{NN}-<n>` branch cut from `origin/main`, not on the claim branch.
   `execution: autonomous`: merge it to trunk now. `stop-at-pr`: open a docs-only PR.
3. Release the claim — only if the branch is still a pure claim (no story commits): remove your
   worktree if you created one, then delete the story doc's exact `branch:` value. The story reads TODO
   again. If story commits already exist (the wrong-premise interrupt fired mid-implementation),
   keep the branch and worktree and name the branch and its last commit in the REPLAN event —
   the story reads DOING until the planner disposes of it.
4. Post `concluded` with `outcome: handback`. Stop. Tell the operator to re-invoke
   `/sprint-orchestrator` on the sprint directory; the next
   plan session resolves the event before planning anything else. Under stop-at-pr the docs PR
   from step 2 must merge BEFORE that re-invocation — the planner sweep reads trunk, and an
   unmerged event is invisible to it; say so in your stop report.

If the operator says continue, record the decision in STORY-FEEDBACK.md and proceed under the
amended understanding.

## Direction stories — `flow: direction`

The deliverable is an investigation dossier, not product code. Steps 0-2 apply unchanged — the
brainstorm gate is where the operator shapes the direction. Then:

- Write the dossier to the sprint directory as `dossier-{NN}.md` on the story branch. The name
  must not match `[0-9]*.md`: `sprint-status.sh` enumerates those as stories, and
  `{NN}-dossier.md` would surface as a phantom second story {NN}.
- Commit it with the story's normal trailer block. By convention the dossier commit is the ONLY
  trailered commit a direction story makes.
- Append a DIRECTION event to STORY-FEEDBACK.md (same id scheme, same immutability), in the same
  commit:

      ## DIRECTION — dr-YYYYMMDD-{NN}-<n> — Story {NN}
      - Dossier: <path>
      - Recommendation: <one line>

- No TDD, no test/typecheck/build gates, no browser evidence: the merge gate is that the diff is
  docs-only. Merge or open a PR per your EXECUTION MODE; the tracker `card.done` intent still
  fires.
- Done means: dossier merged, DIRECTION event appended, and the operator has read the dossier —
  a dossier is an artifact, and human inspection of artifacts is part of done.
- Post `concluded` with `outcome: dossier`, naming the dossier path. Then stop. Re-entering
  planning is the operator's move, in a fresh planner session — never this session, which sits
  in a story worktree on a stale branch.

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

1. a wrong premise or genuine product ambiguity — graded and handled per "Divergences and
   handback";
2. an inability to keep prod green (roll back and report);
3. no approved driver can drive the browser verification.

If an interrupt ends the story, post the terminal `concluded` before stopping: interrupt 1
ends via the handback protocol (`outcome: handback`), interrupt 2 posts `outcome: failed`,
interrupt 3 posts `outcome: blocked`.

## Common mistakes

- Never run `git checkout main` — trunk lives in another worktree; use
  `git switch -c <branch> origin/main`.
- Commits without both trailers — the story ships and sprint status calls it TODO forever.
- A REPLAN or DIRECTION event committed WITH story trailers — flips the story's derived state.
- Naming a dossier `{NN}-dossier.md` — enumerates as a phantom story; the name is
  `dossier-{NN}.md`.
- Checking or deleting `sprint/NN-*` instead of the story doc's exact sprint-scoped `branch:` value.
- Force-pushing after a rejected push. Rebase once, retry once, then stop.
- Deploying from a feature branch instead of merging to trunk first — "live" then ≠ what you
  tested.
- Silently swapping browser drivers — legal only if AGENTS.md approves the driver and the hand-back
  declares it.
- Writing evidence to `/tmp` or into the worktree — both vanish before review.
- Progress pings mid-run — defeats the single-checkpoint purpose. The brainstorm gate (step 2)
  is the sanctioned exception, and it ends when the counterparty says proceed.
- Demanding an in-thread approval ("reply approved" / "type approve" / "reply 'approve spec'")
  from a user who is not this session's counterparty, or inventing a spec/review sign-off the
  plan never asked for — route spec reviews and every other review to the sprint orchestrator via
  the mailbox instead, never to whoever is at your terminal. Handoff-level decisions are already
  approved; only the three interrupts and the brainstorm gate stop you.
