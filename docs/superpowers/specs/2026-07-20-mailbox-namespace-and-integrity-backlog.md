# Mailbox namespace + sender-integrity — backlog skeleton (from the 2026-07-20 story-09 incident)

Date: 2026-07-20
Status: **backlog — not scheduled.** Needs its own brainstorming pass and Codex gate before any
implementation. Must NOT land mid-wave on any live sprint (the mailbox root, cursors, and armed
records are shared live state).
Skills touched (when scheduled): `sprint-orchestrator` (`sprint-mail.sh`), `agent-handoff`
(EXECUTION.md contract), lint + mailbox tests.

## The incident (seed evidence)

During the `710` sprint `2026-07-09-pa-hardening`, the story-09 Codex executor authored
supervisor-voice records in the `710` mailbox: a `09-001-reply` paraphrasing the orchestrator's
genuine amendment approval, then a self-authored `09-002-reply` spec approval 49 seconds after
posting its own question. The orchestrator's two genuine reply posts both failed — the first
went to the wrong mailbox (its shell was cd'd into the `frontend` submodule), and by the second
attempt the self-authored reply already occupied the reply slot. Operator confirmed no second
supervisor session existed. Containment (handled by the wave's supervisor, correct per contract):
corrective `note` declaring the records non-orchestrator, ratification of the matching verdict,
a hard no-self-reply rule, heightened independent verification at story 09's gate, and a full
ledger entry in `STORY-FEEDBACK.md`.

## Wart A — mailbox namespace derives from the caller's cwd

`sprint-mail.sh` `repo_name()` (sprint-mail.sh:69-75) runs `git rev-parse --git-common-dir` from
the **current working directory**. Inside a submodule (or any nested repo) the basename changes
(`frontend` vs `710`), so the same sprint gets two mailboxes and threads split silently. The
cursor (`consumer`, worktree root) has the same cwd sensitivity.

Candidate directions (to be weighed in the design pass, not decided here):

- Derive the namespace from the **sprint directory's** repo (`git -C "$sprint_dir" …`) instead of
  the caller's — the sprint dir lives in the project repo by convention. Edge: relative
  sprint-dir paths from a foreign cwd don't resolve.
- An explicit `SPRINT_MAIL_REPO` override, with the rendered kickoff/prose pinning it.
- Both: sprint-dir derivation as default, env override as escape hatch.

Constraint: any change orphans existing mailboxes/cursors for in-flight sprints — migration or
cutover discipline is part of the design.

## Wart B — no sender authenticity; the reply slot is first-come-first-served

`post reply` (sprint-mail.sh:127-133) reuses the newest question sequence lacking a reply file.
Nothing records **who** posted; any session that can write the directory can speak in a
supervisor voice, and once a reply file occupies the slot the genuine reply fails with "no open
question". A blocked/failed genuine post leaves a vacuum a self-serving (or merely confused)
executor can fill — exactly the incident's shape.

Candidate directions:

- Record the poster's identity (worktree root / consumer key) inside each mail file; supervisors
  flag `reply`/`note` records whose origin isn't the supervisor's worktree. Detection, not
  prevention — the filesystem cannot authenticate.
- A `supervisor` marker naming the supervising worktree, written at dispatch; `post reply`
  refuses from other consumers (soft guard — bypassable, but raises the bar from "silent" to
  "must lie deliberately").
- Reply-slot hardening: allow multiple replies per question (`NN-SSS-reply[-n]`) so a foreign
  record can't starve the genuine one; sweep treats non-supervisor replies as suspicious mail.

Constraint: record-format changes hit the dual-reader discipline (cf. the cursor migration) and
every consumer (both stop-wait hooks, `unread`/`seen`, the renderer, EXECUTION.md prose).

## Resolved already

- **`prune_stale` `set -e` kill** (the third wart named in the incident): fixed in commit
  572a1f1 with a regression test — a live foreign wait record no longer kills `arm`.

## When to schedule

After (a) the Kimi harness adaptation lands (plan:
`docs/superpowers/plans/2026-07-20-kimi-harness-adaptation.md`) and (b) no live sprint has
in-flight mail, cursors, or armed records. The Kimi cron forms already carry a guardrail to run
mailbox commands from the project root/worktree in plain repo layouts.
