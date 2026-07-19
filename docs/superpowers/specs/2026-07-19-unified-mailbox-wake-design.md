# Unified mailbox wake: a main-session Claude Stop hook, one cursor-based wake, epoch retired — design

Date: 2026-07-19
Skills touched: `sprint-orchestrator`, `agent-handoff`
Source: 2026-07-18/19 session — the durable read-cursor landed on `main`
(`docs/superpowers/specs/2026-07-18-mailbox-read-cursor-design.md`), fixing *what* an agent reads
but explicitly deferring the *wake* on idle Claude. This spec closes that for the case that actually
hurt: an idle **main** Claude supervisor session.
Codex gate: two passes, 2026-07-19 (sol/xhigh). Pass 1 rejected the first draft; a headless spike
settled the transport; pass 2 narrowed to two blockers (subagent deadlock, record migration) and
two factual corrections to the author. Both blockers and all corrections are resolved below. A final
live interactive gate (§8) remains, executed as the plan's first task.

## Review + spike (why this is the third revision)

- **The synchronous Stop hook is viable — the 8-block cap resets on real work.** Spike exp1 (pure
  repeated blocking) was overridden at n=9; exp2 (a tool call between each block) ran to n=16
  uncapped. A supervisor does tool-work between wakes, so the cap never bites. The first draft's
  "skip poll on `stop_hook_active`" was itself the bug and is removed.
- **Scope is main Claude sessions only.** `arm`-and-end-turn is inherently a main-session pattern: a
  subagent runs to completion and cannot "end its turn and be woken later." Pass-2 showed a blocking
  `SubagentStop` on a *foreground* in-session subagent deadlocks the parent (the parent can't run to
  post the reply). Rather than spike subagent topology, we **do not** cover subagent executors: the
  hook is wired for `Stop` only; subagent executors do not arm blocking waits (see Non-goals).
- **`asyncRewake` is documented but not adopted.** Correction to the author: it *is* a documented
  command-hook field that promises an idle wake on `exit 2` (not "undocumented for Stop"). It is not
  used because it has no cross-firing dedup (duplicate watchers) and the synchronous main-session
  hook is validated and sufficient. Documented as the future alternative if the topology widens.
- **The record format needs a live-migration story.** Installed files are live (edits deploy on
  `git pull`), and a legacy 4-line record (`line1=pwd`, `line4=numeric epoch`) exists in
  `~/.sprint-mail/.codex-waits/` now. The new hooks must read both formats (§2) or they would misread
  a legacy epoch as a cursor path and wake on everything.
- **Two author errors corrected:** there *is* an existing `Stop` hook (iTerm status) in
  `~/.claude/settings.json`, so the installer must preserve co-installed hooks and prove it; and the
  "no other Stop hook, so parallel-block is moot" claim was wrong (the delay is real but mild — a
  fast status hook still runs; only the Stop *event's completion* is held).

## Problem

1. **Idle main Claude has no wake.** The read-cursor guarantees never-lost *while an agent takes
   steps*, but a supervisor blocked waiting on a reply has no next step. On Codex the Stop hook
   creates it; on Claude the only wake is a backgrounded `sprint-mail.sh wait`, and those are
   unreliable (a run observed them terminated within 1–2 minutes). A *synchronous* Stop hook is not
   reaped that way — a probe held a headless turn open for a clean 20 minutes.
2. **The `since`-epoch is dead weight.** Once the cursor decides *what* is new, the epoch is
   redundant and strictly worse (skips pre-arm unread mail; 1s `stat` resolution). Codex confirmed
   retirement is safe under the append-only + deterministic-naming contract.
3. **Two wake mechanisms disagree.** `codex-stop-wait.sh` filters by `mtime >= since`; the Claude
   path is bare file-existence. The executor's `Mailbox wait:` prose carries two divergent forms.

## Goals

1. **A real main-session Claude wake.** `claude-stop-wait.sh`, wired for `Stop`, holds an ending main
   Claude turn open on an armed record until matching *unread* mail lands or the budget elapses.
   Synchronous; survives where backgrounded waits die.
2. **One wake semantics.** Both hooks wake on the same predicate: a file matching the armed glob
   whose basename is not in the consumer's read-cursor. No timestamps for new records.
3. **Epoch retired for new records; legacy records still honored.** `arm` stops writing `since`; the
   hooks prefer the cursor predicate but keep a legacy-epoch reader so in-flight records survive the
   cutover (§2).
4. **Stable consumer identity.** The cursor is keyed by the git worktree root, and the arm record
   carries the cursor path — so `unread`/`seen`, `arm`, and the hook never disagree, even across
   subdirectories. Hardens `main`'s cursor too.
5. **Idle-main-Claude never-lost upgrades from *human ping* to *hook up to the budget*.** Beyond the
   budget the turn ends and the next-turn cursor sweep still catches everything — late, never lost.

## Non-goals

- **Subagent executors and agent teams are out of scope.** The hook is `Stop`-only. In-session
  subagent executors do not arm blocking waits; a `direct` story that needs a blocking reply is
  mis-scoped and must run as a main-session story instead. `SubagentStop` and `TeammateIdle` are
  explicitly not covered — covering them needs a topology spike this spec does not take.
- **No preemption, no daemon; `asyncRewake` not built.** Synchronous main-session `Stop` only.
- **The cursor stays the single source of truth for what-to-read.** Hooks read it, never write it.
  `sprint-status.sh` never reads the mailbox or the cursor; the mailbox is never state.
- **The deterministic reply wait is unchanged in spirit** — a main-session executor still arms on
  `{NN}-{SSS}-reply.md`; only the predicate (cursor) and Claude transport (hook) change.
- **No rename of `.codex-waits/`** (now shared by both hooks; renaming is cosmetic churn).

## Design

### 1. Consumer identity (foundational — also fixes `main`)

Re-key the read-cursor from `pwd -P` to the **canonicalized git worktree root**
(`root="$(git rev-parse --show-toplevel)"; key="$(cd "$root" && pwd -P)"`), stable across
subdirectories and distinct per worktree. `sprint-mail.sh`'s `cursor_file` (used by `unread`/`seen`)
changes accordingly — a change on `main`, and a strict robustness gain. **Invariant:** one mailbox
consumer per worktree. Outside a git worktree, or in a bare repo, `arm`/`unread`/`seen` fail loudly
(they already require a repo for namespacing); this is stated, not silently handled.

### 2. Arm record + dual-reader migration

`arm` writes a **four-line** record: worktree root, absolute glob(s), timeout, absolute cursor path
(`<mail_dir>/.read/<cksum of worktree root>`). No `since`.

Both hooks are **dual-readers** so live legacy records survive the cutover (edits are live; a legacy
record exists now):

- **Line 4 is a bare integer → legacy record.** Apply the old `mtime >= since` filter with that
  epoch; match identity on line 1 as a physical cwd (string-equal to the hook's `pwd -P`), as today.
- **Line 4 is an absolute path → new record.** Wake on unread-against-that-cursor; match identity on
  line 1 as the worktree root.

The legacy branch is retained until in-flight records drain, then it is dead code a later change may
remove. Both hook suites get explicit legacy-record cases.

**Consumption alone does not drain orphans.** Codex found the on-disk legacy record already 43h past
its budget with a line-1 cwd that no longer exists — since legacy matching needs the hook's exact
`pwd`, no future hook can ever run there to consume it. So a **stale/orphan reaper** is required, not
optional:

- A record is *stale* if its identity path (line 1) is no longer an existing directory, **or** its
  age exceeds its timeout by a margin (both hooks and `arm` can `stat` the record mtime).
- `arm` prunes stale records (any identity) before its double-arm check, so a dead predecessor never
  blocks a fresh arm; `disarm` gains `--stale` to sweep them; `install-claude-hook.sh` runs a
  one-time sweep so the pre-existing orphan is cleared at install. Pruning an orphan is always safe —
  it helps no one.

This is migration-aware duplicate detection: today `arm`/`disarm` match only exact physical cwd, so a
record armed from a subdirectory or a dead worktree is invisible to them; the reaper's
existence-and-age test replaces that exact-match blind spot.

### 3. The unified wake predicate (epoch retirement, new records)

For a new record, a candidate file `f` matching the armed glob wakes the turn iff its basename is
**not** a line in the record's cursor file. Strictly more correct than the epoch: pre-arm unread mail
now wakes (the agent should read it). Codex confirmed the only case the epoch caught that the cursor
misses — rewriting a seen basename — is forbidden by the append-only contract. On wake → `exit 2`
naming the file(s); on budget-elapsed → `exit 2` fallback; record consumed (`rm`) on either exit.

### 4. `claude-stop-wait.sh` (new)

A near-copy of `codex-stop-wait.sh`, differing only where the harness differs:

- **`Stop` only** (main sessions). Not `SubagentStop`.
- **No `stop_hook_active` branch.** The block cap resets on the supervisor's tool-work; the hook
  polls and wakes exactly like the Codex hook.
- **Stdin.** Drain Claude's JSON payload (`cat >/dev/null`).
- **Identity + dual-reader** exactly as §1–§2; same double-arm refusal and foreign-record
  pass-through as the Codex hook.

### 5. `arm` takes an explicit harness

`arm --harness codex|claude` (the kickoff knows the target) replaces the "is a hook wired?" sniff and
verifies the **named** harness's `Stop` reference:

- `--harness codex` → `${CODEX_HOME:-~/.codex}/hooks.json` references `codex-stop-wait.sh`;
- `--harness claude` → a Claude settings file under `${CLAUDE_CONFIG_DIR:-~/.claude}` references
  `claude-stop-wait.sh` in its `Stop` group.

Absent → refuse, naming that harness's installer. **Honest limit (Codex):** a textual reference is
not proof the hook is *active* — Claude has multiple hook sources and disable flags
(`disableAllHooks`, managed policy); Codex hooks are silent-skipped until trusted. `arm` verifies a
reference exists in the expected place; the installers own activation. The absolute "never arm a
record nothing will consume" claim is dropped.

### 6. Wiring and budget

- **`install-claude-hook.sh` (new)** — parity with `install-codex-hook.sh`: **append** the hook to
  the `Stop` group of `${CLAUDE_CONFIG_DIR:-~/.claude}/settings.json`, **preserving co-installed
  hooks** (the iTerm status `Stop` hook is present), idempotent, `timeout: 10860`. Activation is
  resolved in-spec, not deferred: user-settings edits reload automatically (restart is the fallback);
  managed policy / `disableAllHooks` are honest limitations the installer reports if it detects them.
- **Budget.** Default idle-wait budget **3h = 10800s**; hook `timeout` = 10860 (mirrors Codex's
  1800/1860). Targeted reply waits keep `1800`. A parked synchronous hook holds the Stop *event's*
  completion (the co-installed iTerm hook still runs); the interruptibility gate (§8) bounds this,
  and the budget can be cut if that gate fails.

### 7. Prose, lint, tests

**Topology-aware rendering — the subagent form is enforced, not just asserted.** The `Mailbox wait:`
selection is a 2×2 over **{harness: codex | claude} × {topology: main-session | subagent}**, where
topology is a render input the orchestrator supplies at dispatch (it already decides which stories
run as in-session subagents). Only three cells render **arm-and-end-turn**: `(codex, *)` and
`(claude, main-session)`. The fourth cell — **`(claude, subagent)` — renders the non-arming
fallback**: an in-session Claude subagent cannot end-and-be-woken, so its `Mailbox wait:` line is the
existing "do not pretend to wait — treat it as no reply and take the fallback path now" form; a
`direct` story that genuinely needs a blocking reply is mis-scoped and must be re-planned as a
main-session story. `wave-handoffs.sh` and the `agent-handoff` mailbox-wait selection gain the
topology branch (today they branch on harness/`driver_hint` only). A lint pin asserts a rendered
Claude *subagent* kickoff never contains `arm --harness claude`.

**Prose** (main-session Claude only; subagent kickoffs render the non-arming fallback):

- `agent-handoff/EXECUTION.md` — the Claude branch of `Mailbox wait:` flips to
  `sprint-mail.sh arm --harness claude <sprint-dir> {NN}-{SSS}-reply.md 1800`, end the turn, **for a
  main-session executor**; the subagent case takes the fallback path and does not arm.
- `sprint-orchestrator/SKILL.md` — the Claude wave-watch re-arm line becomes `arm --harness claude …`
  and end the turn (the supervisor is always a main session), with the budget note.
- `agent-handoff/SKILL.md`, `sprint-orchestrator/wave-handoffs.sh` — the rendered `Mailbox wait:`
  Claude form branches on topology per above; renderer mirrors the contract.

**`test/lint-skills.sh`** (same commit as pinned prose): update `"stop-wait: since-epoch filter"` to
pin the **dual-reader** — the cursor-path branch is present *and* the legacy-epoch branch is retained
(not "`since` absent," since the migration reader keeps it); `"mail: arm usage line"` gains
`--harness`, drops `[<since-epoch>]`; new pins —
`claude-stop-wait.sh` exists/executable, silent-pass + continuation, `arm --harness` refusal per
harness, `install-claude-hook.sh` exists and preserves co-installed hooks, `INSTALL.md` + both
READMEs name the Claude hook, EXECUTION/SKILL arm-and-end-turn wording, renderer Claude form, **a
rendered Claude subagent kickoff has no `arm --harness claude`** (topology enforcement), and
`disarm --stale` exists.

**Tests:**

- `test-sprint-mail.sh` — cursor keyed by worktree root: **a subdirectory of the same worktree now
  shares the cursor** (inverts the current per-`pwd` case). 4-line record incl. cursor path;
  `--harness` selects the wiring check (wired Claude settings lets `--harness claude` proceed with no
  Codex hook, refuses `--harness codex`). **Reaper:** `arm` prunes a record whose line-1 dir no
  longer exists (and one past its budget) before its double-arm check; `disarm --stale` sweeps them.
- `test-codex-stop-wait.sh` — since-epoch cases → cursor cases; plus a **legacy-record** case (numeric
  line 4 still applies epoch semantics). `arm()` helper writes four lines.
- `test-claude-stop-wait.sh` (new) — no-record pass-through, unread arrival → exit 2, timeout → exit 2
  fallback, double-arm refusal, foreign-record pass-through, and a legacy-record case.
- `test-install-claude-hook.sh` (new) — fresh install wires `Stop`, idempotency, stale-path
  repointing, and **preserves a pre-existing unrelated `Stop` hook**.
- `test-wave-handoffs.sh` — update the pin that asserts the old Claude background-wait form; **add a
  topology case: a Claude subagent kickoff renders the non-arming fallback (no `arm`), a Claude
  main-session kickoff renders arm-and-end-turn.**

### 8. Interruptibility — the live gate (plan's first task, can still reshape the budget)

Before any prose tells a supervisor to arm a multi-hour wait, a **live interactive check** on a real
Claude session must confirm: Esc / a new message cancels a parked hook and returns control; two
sequential wake→work→re-arm cycles run clean; and session exit/resume leaves no orphaned record. If
Esc does not interrupt cleanly, the budget default drops to minutes and we reassess. This is the
plan's first task; the co-installed iTerm `Stop` hook makes clean interruption more than cosmetic.

## Implementation phasing (one spec, one plan)

Codex's phasing, kept as plan ordering: **(1)** shared/version-compatible record semantics — the
worktree-root identity, the 4-line record, the dual-reader, and the stale/orphan reaper — land first
and keep both hooks green on legacy and new records; **(2)** the Claude hook, installer, and
`--harness`; **(3)** prose, lint, READMEs, `INSTALL.md`, and the topology-aware rendering branch. The
interruptibility gate (§8) is task 1 of phase 2 and can veto the budget before any prose changes.

## Files touched

| File | Change |
|---|---|
| `sprint-orchestrator/sprint-mail.sh` | `cursor_file` keyed by canonical worktree root (affects `unread`/`seen`, incl. `main`); `arm --harness`, 4-line record with cursor path, epoch dropped from writes; stale/orphan reaper in `arm`; `disarm --stale` |
| `sprint-orchestrator/codex-stop-wait.sh` | dual-reader: legacy numeric line 4 → epoch semantics, new path line 4 → unread-against-cursor; header update |
| `sprint-orchestrator/claude-stop-wait.sh` | new — `Stop`-only Claude hook; cursor-based + dual-reader; no `stop_hook_active` branch |
| `sprint-orchestrator/install-claude-hook.sh` | new — append to `Stop` preserving co-installed hooks; `timeout: 10860` |
| `sprint-orchestrator/SKILL.md` | Claude wave-watch re-arm → `arm --harness claude`; budget note |
| `agent-handoff/EXECUTION.md` | Claude `Mailbox wait:` → arm-and-end-turn with `--harness`; main-session-only note |
| `agent-handoff/SKILL.md` | rendered `Mailbox wait:` Claude form → arm-and-end-turn |
| `sprint-orchestrator/wave-handoffs.sh` | topology-aware Claude wait form (main-session arms; subagent renders the non-arming fallback) |
| `INSTALL.md` | install, verify, test, report the Claude hook |
| `sprint-orchestrator/test/test-sprint-mail.sh` | worktree-root cursor (subdir shares); 4-line record; `--harness` refuse cases |
| `sprint-orchestrator/test/test-codex-stop-wait.sh` | cursor cases + legacy-record case; `arm()` helper 4 lines |
| `sprint-orchestrator/test/test-claude-stop-wait.sh` | new — Claude hook suite incl. legacy-record case |
| `sprint-orchestrator/test/test-install-claude-hook.sh` | new — installer parity, preserves co-installed hooks |
| `sprint-orchestrator/test/test-wave-handoffs.sh` | update the Claude background-wait-form pin |
| `test/lint-skills.sh` | flip since pin; arm usage `--harness`; new claude-hook/install/preserve pins |
| `sprint-orchestrator/README.md` | Claude hook wiring; drop epoch mentions; budget + parallel-hook note |
| `README.md` (root) | name the Claude hook setup alongside Codex |
