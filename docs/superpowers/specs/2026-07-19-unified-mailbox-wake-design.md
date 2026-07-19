# Unified mailbox wake: a Claude Stop hook, one cursor-based wake, epoch retired — design

Date: 2026-07-19
Skills touched: `sprint-orchestrator`, `agent-handoff`
Source: 2026-07-18 session — the durable read-cursor landed on `main`
(`docs/superpowers/specs/2026-07-18-mailbox-read-cursor-design.md`), fixing *what* an agent reads
but explicitly deferring the *wake* on idle Claude. This spec closes that: give Claude a real Stop
hook and unify both harnesses on one cursor-based wake, retiring the `since`-epoch the cursor made
vestigial. A 2026-07-18 headless probe confirmed a Claude Stop hook honors a large `timeout`
(killed at exactly 900s under a 900 budget; alive to 1200s under a 10800 budget) and is not subject
to the exit-144 reaper that kills backgrounded `sprint-mail.sh wait` tasks.
Codex gate: pending (spec→plan gate, per repo convention).

## Problem

Three things, one root: the wake mechanism is harness-split and still epoch-based, and on Claude it
does not stay alive.

1. **Idle Claude has no wake.** The read-cursor guarantees never-lost *while an agent takes steps*,
   but a supervisor blocked waiting on a single reply has no next step. On Codex the Stop hook
   creates it; on Claude the only wake is a backgrounded `sprint-mail.sh wait`, and those get
   killed within 1–2 minutes (exit 144). So an idle Claude supervisor runs with no watcher and the
   human ping is the de facto wake. A synchronous Stop hook is not reaped that way — the probe held
   a turn open for a clean 20 minutes.

2. **The `since`-epoch is now dead weight.** Once the cursor decides *what* is new, the epoch's job
   ("wake only for mail newer than X") is redundant and strictly worse: it skips pre-arm mail the
   agent never read, and its 1-second `stat` resolution against a `>=` boundary is unorderable. The
   orchestrator already stopped passing it (previous spec). Keeping it is a confusing knob with no
   remaining purpose.

3. **Two wake mechanisms disagree.** `codex-stop-wait.sh` filters by `mtime >= since`; the Claude
   path is bare file-existence. A pattern proven on one does not transfer, and the executor's
   `Mailbox wait:` prose has to carry two divergent forms.

## Goals

1. **A real Claude wake.** `claude-stop-wait.sh` — the structural twin of `codex-stop-wait.sh` —
   holds an ending Claude turn open on an armed record until matching *unread* mail lands or the
   budget elapses. Synchronous, so it survives where backgrounded waits die.
2. **One wake semantics.** Both hooks wake on the same predicate: a file matching the armed glob
   whose basename is not in the cwd's read-cursor. No timestamps anywhere.
3. **Epoch retired everywhere.** `arm` stops computing/storing `since`; the wait record drops from
   four lines to three; `codex-stop-wait.sh` drops the mtime filter; usage, tests, lint, and READMEs
   follow.
4. **Idle-Claude never-lost upgrades from *human ping* to *hook up to the budget*.** Beyond the
   budget the turn ends and the next-turn cursor sweep still catches everything — late, never lost.

## Non-goals

- **No preemption, no daemon.** Unchanged from the cursor spec — the hook fires only at turn end;
  nothing interrupts work in flight.
- **The cursor stays the single source of truth for what-to-read.** Hooks are wake-only; they read
  the cursor, never write it. `sprint-status.sh` still never reads the mailbox or the cursor; the
  mailbox is still never state.
- **The deterministic single-file reply wait is unchanged in spirit** — an executor still arms on
  `{NN}-{SSS}-reply.md`; only the underlying wake predicate (cursor, not epoch) and the Claude
  transport (hook, not background task) change.
- **Codex's poll budget stays 1800** unless a caller passes otherwise — the `arm` timeout is
  per-call, so lengthening Codex waits later is a knob, not a rewrite.
- **No rename of the `.codex-waits/` directory.** It is now shared by both hooks, but renaming ripples
  through both scripts and their tests for a cosmetic gain; keep the name, document that it is shared.

## Design

### 1. The unified wake predicate (epoch retirement)

`arm` writes a **three-line** record (was four): canonical cwd, absolute glob(s), timeout. The
`since` line and the optional `<since-epoch>` argument are removed.

Both `codex-stop-wait.sh` and `claude-stop-wait.sh` replace the `mtime >= since` filter with an
**unread-against-cursor** test. For a candidate file `f` matching the armed glob:

- derive `mail_dir` as the directory of the first glob word (all globs in a record share it);
- the cursor is `mail_dir/.read/<cksum of pwd -P>` — the same key `sprint-mail.sh seen`/`unread`
  use, and the Stop hook runs in the armed cwd, so the key matches;
- `f` wakes the turn iff its basename is **not** a line in that cursor.

This is strictly more correct than the epoch: mail that arrived before `arm` but was never `seen`
now wakes the turn (the agent should read it) instead of being skipped forever. In normal flow the
orchestrator sweeps and `seen`s before arming, so at arm time nothing is unread and the hook waits
for genuinely new mail — the same behavior the epoch intended, without the knob.

On wake → `exit 2` naming the file(s) (continuation prompt). On budget-elapsed → `exit 2` with the
existing fallback message (take the no-reply fallback / re-sweep). The record is consumed (`rm`) on
either exit, exactly as today.

### 2. `claude-stop-wait.sh` (new)

A near-copy of `codex-stop-wait.sh`, differing only where the harness differs:

- **Stdin.** Claude passes a JSON payload; drain it (`cat >/dev/null`), same as the Codex hook
  drains its payload. If the payload's `stop_hook_active` is `true`, do the *guard* (wake
  immediately if something is already unread) but skip the long poll — never re-block for a full
  budget on a loop the harness is already unwinding. (Parsing `stop_hook_active` without `jq` is a
  `grep`-level check; the plan pins the exact grep.)
- **Same record scan** (`.codex-waits/`, this cwd's record, double-arm refusal, foreign-cwd
  pass-through) and **same poll loop** as the Codex hook, using the §1 unread predicate.
- **cwd.** Runs in the session cwd (Claude Stop hooks run in `cwd`), matching the arm record's
  line 1 — the same assumption the Codex hook makes.

### 3. `arm` becomes harness-aware

Today `arm` refuses unless `~/.codex/hooks.json` references `codex-stop-wait.sh`. It now refuses
only if **neither** hook is wired:

- Codex wired: `~/.codex/hooks.json` (or `$CODEX_HOME/hooks.json`) references `codex-stop-wait.sh`, **or**
- Claude wired: a Claude `settings.json` — user (`~/.claude/settings.json`) or project
  (`./.claude/settings.json`) — references `claude-stop-wait.sh`.

If either is present, `arm` proceeds; if neither, it refuses and names **both** installers. The
purpose is unchanged — never arm a record nothing will consume.

### 4. Wiring and budget

- **`install-claude-hook.sh` (new)** — parity with `install-codex-hook.sh`: add the Stop-hook entry
  to `~/.claude/settings.json` (creating/repointing), idempotent, and perform whatever
  activation Claude Code requires for a settings hook. **Open, plan-level:** whether a settings-json
  Stop hook needs an explicit trust/approval step (as Codex's `trusted_hash` does) or is live on
  write — the plan's first research step confirms this against the Claude Code hook docs and shapes
  the installer accordingly.
- **Budget.** Default idle-wait budget **3h = 10800s**; the Claude hook entry's `timeout` = budget +
  60s buffer = **10860** (mirrors Codex's 1800/1860). The hook always exits itself at the record's
  timeout before the harness kill; the settings `timeout` is only a safety net. The idle-supervisor
  `arm` passes `10800`; targeted reply waits keep `1800`.

### 5. Prose

- **`agent-handoff/EXECUTION.md`** — the Claude branch of the `Mailbox wait:` guidance flips from
  "run `sprint-mail.sh wait <...>` as a background task; its completion notification is your wake"
  to the **arm-and-end-turn** form the Codex branch already uses (now that Claude has a hook):
  `sprint-mail.sh arm <sprint-dir> {NN}-{SSS}-reply.md 1800`, end the turn, the hook wakes you.
  "Arming and ending the turn IS the wait" now applies on both harnesses.
- **`sprint-orchestrator/SKILL.md`** — the wave-watch re-arm line, currently "on Claude: run
  `sprint-mail.sh wait` as a background task," becomes "on Claude: `sprint-mail.sh arm ...` and end
  the turn, the Claude Stop hook wakes you" with the budget note for idle waits.
- **`agent-handoff/SKILL.md`** and **`sprint-orchestrator/wave-handoffs.sh`** — the rendered
  `Mailbox wait:` template's Claude form updates to the arm-and-end-turn wording; the renderer must
  keep mirroring the contract.

### 6. Lint and tests

`test/lint-skills.sh` (same commit as the prose it pins):

- **Flip** `"stop-wait: since-epoch filter"` (asserts `since` in `codex-stop-wait.sh`) to a
  cursor pin (e.g. `.read/` present, `since` absent).
- **Update** `"mail: arm usage line"` — the usage line drops `[<since-epoch>]`.
- **New** pins: `claude-stop-wait.sh` exists and is executable; its silent-pass (`exit 0`) and
  continuation (`exit 2`); `arm` accepts the Claude hook (`claude-stop-wait.sh` named in the refuse
  message alongside `install-codex-hook.sh`); `install-claude-hook.sh` exists; READMEs name the
  Claude hook setup; the EXECUTION/SKILL Claude arm-and-end-turn wording; renderer Claude arm form.

Tests:

- **`test/test-sprint-mail.sh`** — arm record assertions drop line 4 (no since epoch) and the
  explicit-since case; add a harness-aware refuse case (a wired Claude `settings.json` lets `arm`
  proceed with no Codex hook).
- **`test/test-codex-stop-wait.sh`** — the two `since-epoch` cases (lines 47–58) become
  cursor cases: a pre-arm file already in the cursor does **not** wake (times out); an unread file
  matching the glob **does** wake. The `arm()` helper writes three lines.
- **`test/test-claude-stop-wait.sh` (new)** — mirror the Codex hook suite for the Claude hook:
  no-record pass-through, unread arrival → exit 2, timeout → exit 2 fallback, double-arm refusal,
  foreign-cwd pass-through, and a `stop_hook_active` case (guard fires, long poll skipped).

### 7. Interruptibility — the one live check the probe could not cover

The headless probe proved the timeout is honored and long, but not that a **user message
interrupts a parked hook**. A 3h hook that makes the supervisor unreachable until mail or timeout
would break the point-of-contact model. The implementation plan's **first step** is a live check:
wire the Claude hook, arm a long wait, confirm Esc / a new message cancels the parked hook and
returns control — before any prose tells a supervisor to arm a multi-hour wait. If it does not
interrupt cleanly, the budget default drops to a few minutes and we reassess.

## Files touched

| File | Change |
|---|---|
| `sprint-orchestrator/claude-stop-wait.sh` | new — Claude Stop hook; cursor-based wake; `stop_hook_active` guard |
| `sprint-orchestrator/install-claude-hook.sh` | new — wire+activate the Claude hook in `settings.json`, `timeout: 10860` |
| `sprint-orchestrator/sprint-mail.sh` | `arm`: harness-aware refuse (Codex or Claude hook); drop `since` (record → 3 lines) + `[<since-epoch>]` usage |
| `sprint-orchestrator/codex-stop-wait.sh` | wake predicate `mtime >= since` → unread-against-cursor; drop the `since` line; header update |
| `sprint-orchestrator/SKILL.md` | Claude wave-watch re-arm → arm-and-end-turn; budget note |
| `agent-handoff/EXECUTION.md` | Claude `Mailbox wait:` branch → arm-and-end-turn (replaces background wait) |
| `agent-handoff/SKILL.md` | rendered `Mailbox wait:` Claude form → arm-and-end-turn |
| `sprint-orchestrator/wave-handoffs.sh` | renderer mirrors the new Claude wait form |
| `sprint-orchestrator/test/test-sprint-mail.sh` | arm record 3 lines; harness-aware refuse case; drop since assertions |
| `sprint-orchestrator/test/test-codex-stop-wait.sh` | since-epoch cases → cursor cases; `arm()` helper 3 lines |
| `sprint-orchestrator/test/test-claude-stop-wait.sh` | new — Claude hook suite |
| `test/lint-skills.sh` | flip since pin; arm usage drop; new claude-hook + harness-aware pins |
| `sprint-orchestrator/README.md` | Claude hook wiring section; drop epoch mentions; budget note |
| `README.md` (root) | name the Claude hook setup alongside Codex |
