# Unified mailbox wake: a Claude Stop hook, one cursor-based wake, epoch retired — design

Date: 2026-07-19
Skills touched: `sprint-orchestrator`, `agent-handoff`
Source: 2026-07-18/19 session — the durable read-cursor landed on `main`
(`docs/superpowers/specs/2026-07-18-mailbox-read-cursor-design.md`), fixing *what* an agent reads
but explicitly deferring the *wake* on idle Claude. This spec closes that: give Claude a real Stop
hook and unify both harnesses on one cursor-based wake, retiring the `since`-epoch the cursor made
vestigial.
Codex gate: 2026-07-19 (sol/xhigh) — flagged the first draft hard (see "Review + spike" below);
its findings are folded in. A follow-up headless spike settled the Claude-transport questions the
review raised. This is the revised spec; a second Codex pass is scheduled before planning.

## Review + spike (why this revision exists)

The first draft proposed a synchronous 3h Claude Stop hook, sniffed which hook was wired, keyed the
cursor by raw `pwd`, and skipped polling on `stop_hook_active`. The Codex gate + a headless spike
(`claude -p --settings` with logging hooks) reshaped it:

- **The synchronous Stop hook is viable — the 8-block cap resets on real work.** Spike exp1 (pure
  repeated blocking, no work) was overridden at n=9; exp2 (a tool call forced between each block)
  ran 15+ cycles uncapped. A supervisor always does tool-work between wakes, so the cap never bites.
  The draft's "skip the poll on `stop_hook_active`" mitigation was itself the bug — it breaks the
  normal wake→work→re-arm loop; it is removed.
- **Subagent executors fire `SubagentStop`, not `Stop`.** Spike exp3: a subagent's completion fired
  `SubagentStop` (with `agent_id`); the main session fired `Stop`. A Stop-only hook misses subagent
  executors. The hook must be wired to **both** events.
- **`asyncRewake` is not adopted.** Spike exp4 showed it sidesteps the block cap (reached n=11) and,
  being async, would not block other Stop hooks — genuinely attractive — but it is undocumented for
  Stop, has no dedup (duplicate watchers), and its one essential property (waking a truly *idle*
  interactive session) is untestable headless. Its sole advantage (not holding the turn) matters
  only when other Stop hooks coexist, which they do not here. Documented as the future alternative;
  not built now.
- **A synchronous hook holds the turn, delaying every *other* Stop hook until it returns**
  (docs-confirmed). Moot today — no other Stop hook is installed — but it makes the budget a
  documented, eyes-open tradeoff, not a free 3h.
- **`pwd` is not a stable consumer identity.** The cursor is re-keyed by the git *worktree root*,
  and the arm record stores the exact cursor path so the hook never recomputes it. This also hardens
  the cursor already on `main`.
- **Harness is made explicit** (`arm --harness codex|claude`) rather than sniffed from hook files.

## Problem

Three things, one root: the wake mechanism is harness-split and still epoch-based, and on Claude it
does not stay alive.

1. **Idle Claude has no wake.** The read-cursor guarantees never-lost *while an agent takes steps*,
   but a supervisor blocked waiting on a reply has no next step. On Codex the Stop hook creates it;
   on Claude the only wake is a backgrounded `sprint-mail.sh wait`, and those are unreliable — a
   second run observed them terminated within 1–2 minutes (exit 144, i.e. signal 16). Whatever the
   exact cause, agent-launched background waits do not survive; a *synchronous* Stop hook does (a
   probe held a headless turn open for a clean 20 minutes).
2. **The `since`-epoch is now dead weight.** Once the cursor decides *what* is new, the epoch's job
   ("wake only for mail newer than X") is redundant and strictly worse: it skips pre-arm mail the
   agent never read, and its 1-second `stat` resolution against a `>=` boundary is unorderable. The
   orchestrator already stopped passing it. Codex independently confirmed retirement is safe under
   the mailbox's append-only + deterministic-naming contract.
3. **Two wake mechanisms disagree.** `codex-stop-wait.sh` filters by `mtime >= since`; the Claude
   path is bare file-existence. A pattern proven on one does not transfer, and the executor's
   `Mailbox wait:` prose carries two divergent forms.

## Goals

1. **A real Claude wake.** `claude-stop-wait.sh`, wired to `Stop` **and** `SubagentStop`, holds an
   ending Claude turn open on an armed record until matching *unread* mail lands or the budget
   elapses. Synchronous; survives where backgrounded waits die.
2. **One wake semantics.** Both hooks wake on the same predicate: a file matching the armed glob
   whose basename is not in the consumer's read-cursor. No timestamps.
3. **Epoch retired everywhere.** `arm` stops computing/storing `since`; `codex-stop-wait.sh` drops
   the mtime filter; usage, tests, lint, and READMEs follow.
4. **Stable consumer identity.** The cursor is keyed by the git worktree root, and the arm record
   carries the cursor path — so `unread`/`seen`, `arm`, and the hook never disagree about which
   cursor is in play, even across subdirectories. Hardens `main`'s cursor too.
5. **Idle-Claude never-lost upgrades from *human ping* to *hook up to the budget*.** Beyond the
   budget the turn ends and the next-turn cursor sweep still catches everything — late, never lost.

## Non-goals

- **No preemption, no daemon.** The hook fires only at turn end; nothing interrupts work in flight.
- **`asyncRewake` is not built** (see Review + spike). Synchronous Stop/SubagentStop only.
- **The cursor stays the single source of truth for what-to-read.** Hooks read the cursor, never
  write it. `sprint-status.sh` never reads the mailbox or the cursor; the mailbox is never state.
- **The deterministic single-file reply wait is unchanged in spirit** — an executor still arms on
  `{NN}-{SSS}-reply.md`; only the wake predicate (cursor, not epoch) and the Claude transport (hook,
  not background task) change.
- **Codex's poll budget stays 1800** unless a caller passes otherwise — `arm`'s timeout is per-call.
- **No rename of `.codex-waits/`.** It is now shared by both hooks; renaming ripples through both
  scripts and their tests for a cosmetic gain. Keep the name; document that it is shared.

## Design

### 1. Consumer identity and the arm record (foundational — also fixes `main`)

Re-key the read-cursor from `pwd -P` to the **git worktree root**
(`git rev-parse --show-toplevel`), which is stable across subdirectories of the same worktree and
distinct per worktree (orchestrator in the main tree, each executor in its own). `sprint-mail.sh`'s
`cursor_file` helper, used by `unread` and `seen`, changes accordingly. This is a change to code on
`main`; it is a strict robustness improvement (a consumer that `cd`s into a subdir no longer
fragments its cursor).

The **arm record gains the cursor path** and keys identity on the worktree root. Four lines:

1. worktree root (identity — the hook matches records whose line 1 equals its own worktree root),
2. absolute glob(s),
3. timeout seconds,
4. absolute cursor path (`<mail_dir>/.read/<cksum of worktree root>`).

The hook reads the cursor path from line 4 instead of recomputing it from `dirname(first glob)` and
its own `pwd` — removing the three-way `pwd` agreement the draft assumed. (The `since` line is gone;
line 4 is now the cursor path.)

### 2. The unified wake predicate (epoch retirement)

Both `codex-stop-wait.sh` and `claude-stop-wait.sh` replace the `mtime >= since` filter with an
**unread-against-cursor** test. For a candidate file `f` matching the armed glob: `f` wakes the turn
iff its basename is **not** a line in the record's cursor file (line 4).

Strictly more correct than the epoch: mail that arrived before `arm` but was never `seen` now wakes
the turn (the agent should read it) instead of being skipped forever. In normal flow the
orchestrator sweeps and `seen`s before arming, so at arm time nothing is unread and the hook waits
for genuinely new mail. Codex confirmed the only case the epoch caught that the cursor misses —
rewriting a previously-seen basename — is forbidden by the append-only contract.

On wake → `exit 2` naming the file(s). On budget-elapsed → `exit 2` with the existing fallback
message. Record consumed (`rm`) on either exit, as today.

### 3. `claude-stop-wait.sh` (new)

A near-copy of `codex-stop-wait.sh`, differing only where the harness differs:

- **Both events.** Installed for `Stop` and `SubagentStop` (spike exp3). The script itself is
  event-agnostic — it scans `.codex-waits/` for a record matching its worktree root and acts.
- **No `stop_hook_active` special-casing.** The spike showed the block cap resets on the tool-work a
  supervisor does between wakes, so the normal wake→work→re-arm loop survives. The hook does **not**
  read or branch on `stop_hook_active`; it polls and wakes exactly like the Codex hook. (The draft's
  skip-the-poll behavior is removed — it broke the loop.)
- **Stdin.** Claude passes a JSON payload; drain it (`cat >/dev/null`).
- **Identity.** Matches records by worktree root (line 1), same double-arm refusal and foreign-record
  pass-through as the Codex hook.

### 4. `arm` takes an explicit harness

Replace the "is a hook wired?" sniff with an explicit `arm --harness codex|claude` (the kickoff
already knows the target transport). `arm` verifies the **named** harness's hook is referenced in
its expected settings:

- `--harness codex` → `${CODEX_HOME:-~/.codex}/hooks.json` references `codex-stop-wait.sh`;
- `--harness claude` → a Claude settings file references `claude-stop-wait.sh`.

If the named harness's reference is absent, `arm` refuses and names that harness's installer.

**Honest limit (Codex):** a textual reference is not proof the hook is *active*. Claude hooks have
several sources (user, project, local, managed, plugin, skill, session) and can be disabled
(`disableAllHooks`, `allowManagedHooksOnly`, `--safe-mode`, `--bare`); Codex hooks are skipped
silently until trusted. `arm` can verify a reference exists; it cannot guarantee consumption. The
spec drops the absolute "never arm a record nothing will consume" claim — the guarantee is "the
named harness's hook is referenced where it should be," and the installers own activation.

### 5. Wiring and budget

- **`install-claude-hook.sh` (new)** — parity with `install-codex-hook.sh`: add the hook to
  `~/.claude/settings.json` under **both** `Stop` and `SubagentStop` (creating/repointing),
  idempotent, `timeout: 10860`. **Plan-level research step:** whether a settings-json hook needs an
  explicit trust/approval step or is live on write — confirmed against the Claude Code hook docs
  before the installer is written; a wired-but-inactive hook is the failure the installer must close.
- **Budget.** Default idle-wait budget **3h = 10800s**; hook entry `timeout` = 10800 + 60 = **10860**
  (mirrors Codex's 1800/1860). The hook exits itself at the record's timeout before the harness kill.
  The idle-supervisor `arm` passes `10800`; targeted reply waits keep `1800`.
  **Eyes-open tradeoff:** a parked synchronous hook delays every other Stop hook's result until it
  returns. This machine has no other Stop hook, so 3h is safe today; the README/INSTALL note states
  the assumption, and the interruptibility gate (§8) bounds the risk.

### 6. Prose

- **`agent-handoff/EXECUTION.md`** — the Claude branch of `Mailbox wait:` flips from "run
  `sprint-mail.sh wait <...>` as a background task" to **arm-and-end-turn**:
  `sprint-mail.sh arm --harness claude <sprint-dir> {NN}-{SSS}-reply.md 1800`, end the turn, the hook
  wakes you. "Arming and ending the turn IS the wait" now applies on both harnesses.
- **`sprint-orchestrator/SKILL.md`** — the Claude wave-watch re-arm line becomes `arm --harness
  claude ...` and end the turn, with the idle-wait budget note.
- **`agent-handoff/SKILL.md`** and **`sprint-orchestrator/wave-handoffs.sh`** — the rendered
  `Mailbox wait:` Claude form updates to arm-and-end-turn (with `--harness`); the renderer keeps
  mirroring the contract.

### 7. Lint and tests

`test/lint-skills.sh` (same commit as the prose it pins):

- **Flip** `"stop-wait: since-epoch filter"` (`since` in `codex-stop-wait.sh`) to a cursor pin
  (`.read/` present, `since` absent).
- **Update** `"mail: arm usage line"` — usage gains `--harness`, drops `[<since-epoch>]`.
- **New** pins: `claude-stop-wait.sh` exists/executable, silent-pass (`exit 0`) and continuation
  (`exit 2`); it is wired for `SubagentStop` as well as `Stop` (installer + README); `arm --harness`
  refuses per named harness; `install-claude-hook.sh` exists; `INSTALL.md` and both READMEs name the
  Claude hook setup; the EXECUTION/SKILL Claude arm-and-end-turn wording; renderer Claude arm form.

Tests:

- **`test/test-sprint-mail.sh`** — cursor keyed by worktree root: a **subdirectory of the same
  worktree now shares the cursor** (inverts the old per-`pwd` case at the current
  `test-sprint-mail.sh` cursor block). Arm record is 4 lines incl. the cursor path; `--harness`
  selects the wiring check; a wired Claude `settings.json` lets `arm --harness claude` proceed with
  no Codex hook, and refuses `--harness codex`.
- **`test/test-codex-stop-wait.sh`** — the two `since-epoch` cases become cursor cases: a matching
  file already in the cursor does **not** wake (times out); an unread match **does** wake. The
  `arm()` helper writes four lines incl. the cursor path.
- **`test/test-claude-stop-wait.sh` (new)** — mirror the Codex hook suite: no-record pass-through,
  unread arrival → exit 2, timeout → exit 2 fallback, double-arm refusal, foreign-record
  pass-through. (No `stop_hook_active` branch to test — there is none.)
- **`test/test-install-claude-hook.sh` (new)** — parity with `test-install-codex-hook.sh`: fresh
  install wires both `Stop` and `SubagentStop`, idempotency, stale-path repointing.

### 8. Interruptibility — the live gate (before planning-completion, not a footnote)

The spike proved the timeout is honored and long, but not that a **user message interrupts a parked
hook** — and §5's parallel-hook delay makes this more than cosmetic. Before the plan's prose tells a
supervisor to arm a multi-hour wait, a **live interactive check** must confirm, on a real Claude
session: Esc / a new message cancels a parked hook and returns control; and two sequential
wake→work→re-arm cycles plus session exit/resume leave no orphaned record. If Esc does not interrupt
cleanly, the budget default drops to minutes and we reassess. This is the plan's first task and its
result can still reshape the budget.

## Files touched

| File | Change |
|---|---|
| `sprint-orchestrator/sprint-mail.sh` | `cursor_file` keyed by worktree root (affects `unread`/`seen`, incl. `main`); `arm --harness codex\|claude`, 4-line record with cursor path, epoch dropped |
| `sprint-orchestrator/claude-stop-wait.sh` | new — Claude Stop/SubagentStop hook; cursor-based wake; no `stop_hook_active` branch |
| `sprint-orchestrator/install-claude-hook.sh` | new — wire+activate under `Stop` and `SubagentStop`, `timeout: 10860` |
| `sprint-orchestrator/codex-stop-wait.sh` | wake predicate `mtime >= since` → unread-against-cursor (read cursor path from record); drop the `since` line; header update |
| `sprint-orchestrator/SKILL.md` | Claude wave-watch re-arm → `arm --harness claude` and end the turn; budget note |
| `agent-handoff/EXECUTION.md` | Claude `Mailbox wait:` branch → arm-and-end-turn with `--harness` |
| `agent-handoff/SKILL.md` | rendered `Mailbox wait:` Claude form → arm-and-end-turn |
| `sprint-orchestrator/wave-handoffs.sh` | renderer mirrors the new Claude wait form |
| `INSTALL.md` | install, verify, test, and report the Claude hook (both events) |
| `sprint-orchestrator/test/test-sprint-mail.sh` | worktree-root cursor (subdir shares); 4-line record; `--harness` refuse cases |
| `sprint-orchestrator/test/test-codex-stop-wait.sh` | since-epoch cases → cursor cases; `arm()` helper 4 lines |
| `sprint-orchestrator/test/test-claude-stop-wait.sh` | new — Claude hook suite |
| `sprint-orchestrator/test/test-install-claude-hook.sh` | new — installer parity suite (both events) |
| `test/lint-skills.sh` | flip since pin; arm usage `--harness`; new claude-hook/SubagentStop/install pins |
| `sprint-orchestrator/README.md` | Claude hook wiring (both events); drop epoch mentions; budget + parallel-hook note |
| `README.md` (root) | name the Claude hook setup alongside Codex |
