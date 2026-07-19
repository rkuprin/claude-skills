# Durable mailbox read-cursor: never-lost mail, noticed at the next step — design

Date: 2026-07-18
Skills touched: `sprint-orchestrator`, `agent-handoff`
Source: operator observation, 2026-07-18 — a story-06 brainstorm-gate `question` posted at 09:03
was not surfaced by the orchestrator's re-arm watcher for ~10 minutes; and a second run showed a
Claude supervisor with no live watcher at all. Direction settled interactively the same session:
prioritize as "noticed on the next step, never lost" — no preemption, no daemon.
Codex gate: 2026-07-18 (sol/xhigh) — the run timed out before its final synthesis, but its
salvaged reasoning reframed the root cause from "epoch gap" to **wake-liveness** (folded in below);
its own "600s hook-kill" hypothesis was checked and refuted (installer sets `timeout: 1860`).

## Problem

Two failures are tangled together. The **dominant** one is *wake-liveness*: the thing meant to
notice mail does not stay alive (items 4–5 below). The **secondary** one is that the mtime
`since`-epoch used to decide "what is new" is fragile (items 1–3). The original 09:03 diagnosis
blamed only the epoch gap; the wider truth is that on the harness the supervisor actually runs on
(Claude), *nothing was watching at all*. The cursor in this spec fixes the epoch class outright and
makes every look exact and cheap; the wake-liveness fix (a Claude Stop hook) is a separate,
now-de-risked follow-up (see the note under Non-goals).

Mail detection rides on a single `since`-epoch watermark: the Codex Stop hook
(`codex-stop-wait.sh`) wakes the turn only for mail whose `mtime >= since`. That one number is
asked to do three unrelated jobs, and it is unreliable at two of them.

1. **"What is new" is a hand-set epoch that is easy to set at the wrong instant.** `arm` defaults
   `since` to `date +%s`. The orchestrator prose (`sprint-orchestrator/SKILL.md`) tells the agent
   to note the epoch at sweep time and re-arm with it, but it is trivial to note it at *arm* time
   instead — after processing the previous batch. Mail arriving during that processing then has
   `mtime < arm-epoch` and is skipped forever, because each re-arm advances `since` past it. This
   is the 09:03 miss. Even set correctly, `stat -f %m` is 1-second resolution against a `>=`
   boundary: two files in the same second are unorderable, so no epoch value is simultaneously
   gap-free and duplicate-free.

2. **Detection only happens at turn boundaries — never during work.** The Codex path is a
   busy-wait *inside the Stop hook*; it runs only when the turn is already ending. The Claude path
   (`sprint-mail.sh wait` as a background task) surfaces only at the next yield/re-arm. Neither is
   a watcher in the always-running sense. Mail landing mid-task is structurally invisible until
   the next boundary.

3. **A missed wake is a missed *read*, not a late one.** "Unread" is computed from a timestamp,
   not stored. So a skipped re-arm (a per-turn discipline the model must never forget), or a
   post-timeout turn that moved on, drops that mail from the agent's attention with nothing to
   reconcile it later.

4. **Wake-liveness — the dominant failure, and harness-asymmetric.** On Codex the Stop hook is
   fine (installer sets `timeout: 1860`). On **Claude there is no Stop hook at all**; the only wake
   is a backgrounded `sprint-mail.sh wait`, and those get **killed within 1–2 minutes (exit 144)** —
   so the supervisor runs with *no watcher*, and the human "how's it going" ping has been the de
   facto wake. The two paths also disagree on what "new" means (Codex: mtime watermark; Claude:
   bare file-existence), so a pattern proven on one does not transfer.

5. **A two-glob `wait` false-fires on stale mail.** `sprint-mail.sh wait` (the Claude path) is
   pure existence — no `since` filter — and its `$pat` is unquoted, so a wait like
   `'NN-*-question.md NN-*-concluded.md'` returns on the *first* existing match. A stale
   `concluded` from earlier satisfies a fresh wait instantly, waking the agent with nothing new.
   Confirmed in code (`sprint-mail.sh` lines 98–108).

## Goals

1. **Never lost — in two regimes, stated honestly.** *While the agent is taking steps*, the
   start-of-step sweep against the durable cursor reads all unread mail regardless of whether any
   wake fired; worst case degrades from *lost* to *late*. *While the agent is fully idle* (blocked
   waiting, no next step), never-lost still needs a wake to create the next step — on Codex the
   Stop hook, on Claude the human ping today (the follow-up Claude Stop hook later). The cursor
   makes the eventual look exact; it does not, by itself, cause an idle agent to look.
2. **Noticed at the next step.** The consumer surfaces unread mail at the start of each turn /
   numbered step, bounded by step size — not by a wake that may never come.
3. **Prioritized without preemption.** Reading mail is the first action of a step, ahead of other
   work; within a sweep, blocking kinds (`question`, `concluded`) are read before informational
   ones. No interruption of in-flight work.
4. **Detection is exact and timestamp-free** — a set difference over filenames, not an epoch
   comparison. This removes the entire class of gap/duplicate/off-by-one-second bugs.

## Non-goals

- **No preemption, no daemon.** Nothing interrupts a running turn; no external launchd/tmux
  watcher injects messages. Explicitly rejected in favor of the checkpoint-sweep guarantee.
- **No change to the Codex Stop hook or the `since`-epoch mechanism.** `codex-stop-wait.sh` and the
  `arm`/`disarm` surface stay exactly as they are. The hook remains a best-effort *latency nudge*
  for the idle-wait case; it is no longer the source of truth for what gets read, so its epoch no
  longer needs to be correct. (Retiring the epoch and unifying both harness paths behind the cursor
  is a possible fast-follow, out of scope here — it would churn proven hook code and its tests for
  latency-only gains.)
- **In scope, though:** the two-glob `wait` stale-match bug (Problem §5). Sweeps move to the new
  cursor-aware `unread` (below), which excludes already-seen files, so a stale `concluded` can no
  longer false-fire a sweep. The *deterministic single-file* reply wait (`arm`/`wait` on
  `{NN}-{SSS}-reply.md`) is unchanged — it is already exact.
- **Follow-up, out of scope here (own spec):** a Claude Stop hook (`claude-stop-wait.sh`) as a
  cursor-guard, to give an idle Claude supervisor a real wake and close the exit-144 class. It is
  now de-risked: a 2026-07-18 probe confirmed Claude honors a large Stop-hook `timeout` and holds
  the turn for at least 20 minutes uninterrupted (probe: `timeout 900` killed at 898s; `timeout
  10800` alive to a 1200s self-cap) — not subject to the 1–2 min reaper that kills backgrounded
  waits. It depends on this cursor existing (the guard is a `unread` query), so it sequences after.
- **The cursor is not sprint state.** `sprint-status.sh` never reads it; story state stays
  git-derived. Deleting a cursor loses nothing — worst case a consumer re-reads already-seen mail
  once. The mailbox-is-never-state boundary is preserved verbatim.
- **No new frontmatter keys, no change to message kinds, sequencing, or the deterministic
  `reply` wait.** The executor's one-open-question reply-wait (`arm`/`wait` on
  `{NN}-{SSS}-reply.md`) is untouched.

## Design

### 1. The primitive: a durable per-consumer read-cursor

Replace "is this mail newer than an epoch?" with "have I read this file?" — stored, not computed.

- **Location**: `<mail_dir>/.read/<key>`, one cursor file per consumer, holding one consumed mail
  basename per line. It lives *inside* the sprint's mail dir, so it is namespaced per sprint for
  free and is disposed when the mailbox is disposed. `<mail_dir>` is unchanged:
  `$MAIL_ROOT/<repo>/<sprint-basename>/`.
- **`<key>`** is a filesystem-safe encoding of the consumer's `pwd -P` (the same canonical cwd the
  Stop hook and `.codex-waits` already key on). Because the orchestrator sits in the main worktree
  and each executor in its own, they resolve to independent cursors automatically. The exact
  encoding is a plan-level mechanical choice (a `cksum` of the path, or scan-by-first-line as
  `.codex-waits` does); it must be deterministic and stable within a session.
- **`.read/` is invisible to `list`**: `list` matches `^NN-SSS-` on `ls` output, which skips the
  dot-directory. `list` stays cursor-blind and raw — useful for humans and debugging.
- **Unread-for-me** = files matching my glob(s) of interest, minus the basenames in my cursor.
  Pure set difference: no timestamps, no boundary, no epoch knob.

Single-writer safety: each cursor is owned by exactly one consumer cwd, so appends never race —
no lock needed (consistent with the bash-3.2, no-`flock` constraint).

### 2. Two new `sprint-mail.sh` subcommands

Both sit beside the existing `post`/`list`/`wait`/`arm`/`disarm`, coreutils-only, and are purely
additive — no existing command changes behavior.

- `unread <sprint-dir> <name-or-glob(s)>` — lists mail matching the glob(s) whose basename is
  **not** in this cwd's cursor, mtime-ordered (same ordering as `list`). Accepts space-separated
  globs like `arm`. Prints nothing and exits 0 when all matches are already seen. The caller
  controls prioritization through the glob: sweep `'*-question.md *-concluded.md'` first, then a
  broader glob for the rest.
- `seen <sprint-dir> <file>...` — appends the given basenames (full paths or basenames accepted)
  to this cwd's cursor, creating `.read/` on first use. Idempotent: re-marking a seen file is
  harmless (membership is set semantics). The reader calls it immediately after reading, before
  moving on.

### 3. The policy — sweep first, blocking kinds first (the prose half)

**Orchestrator** (`sprint-orchestrator/SKILL.md`, the "watch the mailbox reactively" section,
currently lines ~202–211). The epoch dance ("note the epoch (`date +%s`) … re-arm with the epoch
of that sweep") is removed. It becomes:

- The **first action of every turn** is `sprint-mail.sh unread <sprint-dir>
  '*-question.md *-concluded.md'`, read those, then a broader `unread <sprint-dir> '*'` for
  informational mail — *before* any other supervision work. This sweep, against the durable
  cursor, is what makes mail never-lost: even with zero wake from the hook, the next turn catches
  it.
- After reading, `sprint-mail.sh seen <sprint-dir> <files…>`.
- Then re-arm as today — `sprint-mail.sh arm <sprint-dir> '*-question.md *-concluded.md' 1800`
  — but the agent no longer computes or passes a `<since>` epoch. The default (`now`) is fine
  because the arm is now only an idle-latency nudge; a spurious wake finds nothing unread and
  re-arms, a missed wake is caught by the next sweep. Both are harmless.

**Executor** (`agent-handoff/EXECUTION.md`, the note-check at ~line 141). "Check for new `note`
messages at each numbered step boundary, and read all of your story's notes before merge or PR"
becomes a cursor-aware sweep: at each numbered step boundary run `sprint-mail.sh unread
<sprint-dir> '{NN}-*-note.md'`, read them, `seen` them; a note is thus never missed nor re-read.
The deterministic `reply` wait (`arm`/`wait` on `{NN}-{SSS}-reply.md`) is unchanged — it is
already exact.

### 4. How the failure modes close

| Was failing | After |
|---|---|
| Epoch gap window + 1s mtime ambiguity (§1) | gone — `unread` is a filename set difference, no epoch |
| Detection only at turn-end (§2) | the start-of-step `unread` sweep catches mail with zero wake |
| Missed wake = lost (§3) | = late (while stepping); unread persists in the cursor's complement until `seen` |
| Two-glob `wait` false-fires on stale mail (§5) | sweeps use `unread`, which excludes seen files — no stale match |
| Harness watermark-vs-existence disagreement (§4) | both consult the same cursor via `unread` |
| Wake-liveness on idle Claude (§4) | **not fixed here** — the follow-up Claude Stop hook; today the human ping |

### 5. Lint and tests (bash + grep only)

`test/lint-skills.sh` — same commit as the prose it pins (repo rule):

- **Flip** pin `"orchestrator: re-arm after each sweep"` (currently asserts the string
  `"re-arm with the epoch of that sweep"`, line ~94): that phrase is removed, so the pin must
  change to assert the new cursor rule instead — e.g. `sprint-mail.sh unread` present in the
  orchestrator watch section, and the epoch-dance phrase *absent*.
- **Keep** pin `"orchestrator: supervisor arm globs"` (`'*-question.md *-concluded.md'`, line
  ~93) — still valid, `unread` and `arm` share the glob. Keep `"orchestrator: mailbox never
  state"` and `"orchestrator: reactive mailbox watch"`.
- **Keep untouched** the hook pins (`"stop-wait: since-epoch filter"`, line ~254) and the
  `arm`/`disarm` usage pins — the surgical scope leaves them green.
- **New** pins: `unread`/`seen` usage lines present in `sprint-mail.sh`; the orchestrator
  "sweep unread first" rule; the executor step-boundary `unread` note-sweep in EXECUTION.md; a
  cursor-never-state clause in both SKILL.md and EXECUTION.md.

`sprint-orchestrator/test/test-sprint-mail.sh` — new cases:

- `unread` returns only mail not yet `seen`, mtime-ordered.
- `seen` marks basenames; a subsequent `unread` over the same glob excludes them.
- Cursor is per-cwd: two distinct cwds have independent unread sets over one mail_dir.
- Cursor is per-sprint: a different sprint dir yields an independent cursor.
- `unread` accepts multiple space-separated globs.
- **Two-glob stale-match (§5 regression guard):** with an older `concluded` already present and
  `seen`, a two-glob `unread '*-question.md *-concluded.md'` returns nothing until a genuinely new
  file lands — i.e. `unread` does not false-fire the way `wait` did.
- `seen` is idempotent (re-marking is harmless).
- `.read/` is invisible to `list` (list output byte-identical with and without a cursor present).
- `seen` on a fresh mailbox creates `.read/` and its cursor.

Existing suites stay green: `test/lint-skills.sh`, `test-sprint-mail.sh`, `test-sprint-status.sh`,
`test-wave-handoffs.sh`, `test-codex-stop-wait.sh`.

## Files touched

| File | Change |
|---|---|
| `sprint-orchestrator/sprint-mail.sh` | new `unread` and `seen` subcommands; usage block; header comment for the `.read/` cursor |
| `sprint-orchestrator/SKILL.md` | orchestrator watch section: epoch dance → sweep-`unread`-first, blocking kinds first, `seen`, plain `arm`; cursor-never-state clause |
| `agent-handoff/EXECUTION.md` | executor note-check → cursor-aware `unread` sweep at each step boundary + `seen`; cursor-never-state clause |
| `sprint-orchestrator/test/test-sprint-mail.sh` | new `unread`/`seen` cases per §5 |
| `test/lint-skills.sh` | flip the epoch-dance pin; new cursor pins; same commit as the prose |
