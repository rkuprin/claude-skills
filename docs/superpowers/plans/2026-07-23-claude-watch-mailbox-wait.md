# Claude Watch Mailbox Wait Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the blocking Claude Stop-hook mailbox wait with a background `sprint-mail.sh watch` task that wakes the session via a harness event while the operator keeps the prompt.

**Architecture:** A new cursor-aware `watch` subcommand in `sprint-mail.sh` (one atomic stdout line per terminal outcome, per-worktree lockfile with PID-liveness) is launched as a Claude Code background task — Monitor-primary with a Bash `run_in_background` fallback clause, confirmed by a Phase 0 probe. The Claude arm/record/Stop-hook path is retired with an ordered migration; Codex and Kimi transports are untouched.

**Tech Stack:** bash 3.2 (macOS), grep-only tests, Claude Code background-task tools. No new runtimes.

**Spec:** `docs/superpowers/specs/2026-07-23-claude-monitor-mailbox-wait-design.md` (revision including the 2026-07-23 second-round review record) — read it before starting any task.

## Global Constraints

- bash 3.2 compatible, no `flock`, no `jq`/YAML parsers; tests are bash + grep only (repo rule).
- Every commit that changes pinned prose updates `test/lint-skills.sh` in the SAME commit — including REMOVING negative pins the new design inverts (`hasnt … "as a background task"` at lint lines ~242, ~294, ~352, and the matching wave-handoffs case): a passing pin that no longer guards a real invariant is worse than none.
- Watch protocol: exactly ONE stdout line per terminal outcome (wake exit 0, timeout exit 1, error exit 2 with the line mirrored to stderr). Pre-dispatch failures (`usage`, `err` in `repo_name()`) must also emit the one stdout line when the command is `watch`.
- Wake events are nudges, never state: the woken session sweeps (`unread`/`seen`) before acting; prose must say so.
- Lock staleness: recorded PID no longer alive OR age > 2 × the lock's recorded timeout. Test fixtures that need a FRESH lock must record a live PID (use `$$`), never a made-up number.
- Budgets: supervisor idle sweep 10800s, targeted reply waits 1800s. Poll: `SPRINT_MAIL_POLL`, default 20s.
- Rendered commands single-quote the sprint dir and globs; the `~/...` script path stays UNQUOTED (tilde must expand). Sprint dirs are `docs/sprints/YYYY-MM-DD-<slug>` — no spaces or apostrophes (stated constraint, no escaping helper).
- Default launcher in all rendered text: **Monitor** (`persistent: true`, description `"sprint mailbox"`), with the inline fallback clause "no Monitor tool in this session? launch the same command with Bash `run_in_background: true`".
- Codex/Kimi wait paths must not change behavior; `.codex-waits` records are never bulk-deleted, and live-vs-dead is decided by OPERATOR CONFIRMATION, never inferred from age/PID/timeout.
- Verification commands must never pipe a suite's exit status away: run the suite to a file, `echo "exit=$?"`, then inspect the file.
- Conventional commits; stage explicit paths only; never `git add -A` and never `git add -u <dir>`.

---

### Task 1: `sprint-mail.sh watch` subcommand

**Files:**
- Modify: `sprint-orchestrator/sprint-mail.sh` (usage lines 4-11 and 45-57, `err()`/`usage()` lines 45-58, header comment lines 23-34, helpers after `cursor_file()` ~line 118, new `watch)` case after `wait)` ~line 225)
- Test: `sprint-orchestrator/test/test-sprint-mail.sh` (append before the summary block at the end)

**Interfaces:**
- Consumes: existing `cursor_file()`, `$consumer`, `$mail_dir`, `$POLL`.
- Produces: `sprint-mail.sh watch <sprint-dir> <name-or-glob(s)> [<timeout>]` — exit 0 one wake line, exit 1 one timeout line, exit 2 one error line (stdout, mirrored to stderr, INCLUDING pre-dispatch errors); helpers `watch_lock()` (prints lock path) and `watch_lock_stale <lock>` (exit 0 if stale: dead PID or age > 2×timeout). Lock dir `<mail_dir>/.watch/`, lock format: line 1 PID, line 2 timeout. Tasks 2-6 rely on these exact semantics.

- [ ] **Step 1: Write the failing tests**

Append to `sprint-orchestrator/test/test-sprint-mail.sh`, immediately before its final summary block (the `printf` of PASS/FAIL at the bottom). Note `one_line()` — asserts non-empty AND exactly one line, because `printf '%s\n' "" | wc -l` is 1 and would false-pass on empty output:

```bash
# ---- watch: cursor-aware background wait — ONE stdout line per outcome ----
one_line() { [ -n "$1" ] && [ "$(printf '%s\n' "$1" | wc -l | tr -d ' ')" = "1" ]; }
# Fresh sprint fixture so timeout cases see an empty mailbox.
SPRINT_W="docs/sprints/2026-07-23-watch-fixture"
WDIR="$SPRINT_MAIL_ROOT/repo-alpha/2026-07-23-watch-fixture"
WLOCK="$WDIR/.watch/$(printf '%s\n' "$(cd "$REPO_A" && pwd -P)" | cksum | cut -d' ' -f1)"

# wake on pre-existing unread mail: immediate, one line, exit 0, lock cleaned
wq="$(printf 'which flow?\n' | "$SUT" post "$SPRINT_W" 11 question -)"
out="$("$SUT" watch "$SPRINT_W" '11-*-question.md' 20)"; rc=$?
[ "$rc" = 0 ] && ok "watch wakes on pre-existing unread mail (exit 0)" || no "watch wakes on pre-existing unread mail (rc=$rc)"
echo "$out" | grep -q "New sprint mail arrived: .*11-001-question.md" \
  && ok "watch wake line names the mail file" || no "watch wake line names the mail file (got: $out)"
one_line "$out" && ok "watch wake is exactly one stdout line" || no "watch wake is exactly one stdout line (got: $out)"
[ ! -f "$WLOCK" ] && ok "watch removes its lock on wake" || no "watch removes its lock on wake"

# seen mail does not wake: cursor-aware timeout, supervisor-glob guidance, exit 1
"$SUT" seen "$SPRINT_W" 11-001-question.md
out="$("$SUT" watch "$SPRINT_W" '11-*-question.md 11-*-concluded.md' 2)"; rc=$?
[ "$rc" = 1 ] && ok "watch times out on seen-only mail (exit 1)" || no "watch times out on seen-only mail (rc=$rc)"
echo "$out" | grep -q "Mailbox watch timed out after 2s" \
  && ok "watch timeout line present" || no "watch timeout line present (got: $out)"
echo "$out" | grep -q "sweep ALL new mail" \
  && ok "question-glob timeout carries supervisor guidance" || no "question-glob timeout carries supervisor guidance (got: $out)"
one_line "$out" && ok "timeout is exactly one stdout line" || no "timeout is exactly one stdout line (got: $out)"

# reply-glob timeout carries the executor fallback guidance
out="$("$SUT" watch "$SPRINT_W" '11-*-reply.md' 2)"
echo "$out" | grep -q "no-reply fallback" \
  && ok "reply-glob timeout carries executor guidance" || no "reply-glob timeout carries executor guidance (got: $out)"
one_line "$out" && ok "reply timeout is one line" || no "reply timeout is one line"

# note-glob timeout carries the dependency-park guidance
out="$("$SUT" watch "$SPRINT_W" '11-*-note.md' 2)"
echo "$out" | grep -q "dependency park" \
  && ok "note-glob timeout carries park guidance" || no "note-glob timeout carries park guidance (got: $out)"
[ ! -f "$WLOCK" ] && ok "watch removes its lock on timeout" || no "watch removes its lock on timeout"

# mail landing mid-poll wakes the loop
( sleep 2; printf 'late finding\n' | "$SUT" post "$SPRINT_W" 12 evidence - >/dev/null ) &
out="$("$SUT" watch "$SPRINT_W" '12-*-evidence.md' 20)"; rc=$?
wait
[ "$rc" = 0 ] && echo "$out" | grep -q "12-001-evidence.md" \
  && ok "watch wakes on mail landing mid-poll" || no "watch wakes on mail landing mid-poll (rc=$rc out=$out)"

# lock conflict: a fresh LIVE-pid lock refuses a second watch, line on stdout AND stderr
mkdir -p "$WDIR/.watch"
printf '%s\n1800\n' "$$" > "$WLOCK"
out="$("$SUT" watch "$SPRINT_W" '11-*-reply.md' 2 2>"$TMP/watch.err")"; rc=$?
[ "$rc" = 2 ] && echo "$out" | grep -q "already running" \
  && ok "second watch refused while lock is fresh (exit 2)" || no "second watch refused while lock is fresh (rc=$rc out=$out)"
grep -q "already running" "$TMP/watch.err" \
  && ok "watch error is mirrored to stderr" || no "watch error is mirrored to stderr"
one_line "$out" && ok "lock-conflict error is one stdout line" || no "lock-conflict error is one stdout line"

# dead-PID lock is stale even when young: pruned, watch proceeds to timeout
deadpid="$(sh -c 'echo $$')"
printf '%s\n1800\n' "$deadpid" > "$WLOCK"
out="$("$SUT" watch "$SPRINT_W" '11-*-reply.md' 2)"; rc=$?
[ "$rc" = 1 ] && ok "dead-PID lock pruned, watch proceeds" || no "dead-PID lock pruned, watch proceeds (rc=$rc out=$out)"

# old lock with a live PID is pruned by the age backstop
printf '%s\n1800\n' "$$" > "$WLOCK"
touch -t 202601010000 "$WLOCK"
out="$("$SUT" watch "$SPRINT_W" '11-*-reply.md' 2)"; rc=$?
[ "$rc" = 1 ] && ok "aged lock pruned by the 2x-timeout backstop" || no "aged lock pruned by the age backstop (rc=$rc out=$out)"

# error protocol covers pre-dispatch and validation failures on stdout
out="$("$SUT" watch "$SPRINT_W" 'sub/dir.md' 2 2>/dev/null)"; rc=$?
[ "$rc" = 2 ] && echo "$out" | grep -q "not a path" \
  && ok "watch rejects path-shaped pattern on stdout" || no "watch rejects path-shaped pattern (rc=$rc out=$out)"
out="$("$SUT" watch "$SPRINT_W" '11-*-reply.md' soon 2>/dev/null)"; rc=$?
[ "$rc" = 2 ] && one_line "$out" \
  && ok "watch rejects non-numeric timeout with one stdout line" || no "watch rejects non-numeric timeout (rc=$rc out=$out)"
out="$("$SUT" watch "$SPRINT_W" 2>/dev/null)"; rc=$?
[ "$rc" = 2 ] && one_line "$out" \
  && ok "watch with missing pattern emits one stdout line" || no "watch with missing pattern emits one stdout line (rc=$rc out=$out)"
out="$(cd /tmp && "$SUT" watch "$SPRINT_W" '11-*-reply.md' 2 2>/dev/null)"; rc=$?
[ "$rc" = 2 ] && one_line "$out" \
  && ok "watch outside a repo emits one stdout line" || no "watch outside a repo emits one stdout line (rc=$rc out=$out)"
```

- [ ] **Step 2: Run tests to verify the load-bearing ones fail**

Run: `sprint-orchestrator/test/test-sprint-mail.sh > "$TMP_OUT" 2>&1; echo "exit=$?"; grep '^FAIL' "$TMP_OUT"` (any scratch path for `$TMP_OUT`).
Expected: nonzero exit; the wake, timeout-guidance, mid-poll, lock-conflict, stderr-mirror, and one-stdout-line-on-error cases FAIL. KNOWN false-passes at red stage (fine, they harden later steps): the two `[ ! -f "$WLOCK" ]` cleanup checks and the two stale-lock cases pass trivially while `watch` doesn't exist. All pre-existing cases still pass.

- [ ] **Step 3: Implement `watch`**

In `sprint-orchestrator/sprint-mail.sh`:

(a) Add to the header usage list (after the `wait` line, both in the top comment and in `usage()`):

```
sprint-mail.sh watch <sprint-dir> <name-or-glob(s)> [<timeout-seconds>]
```

(b) Make the shared error paths watch-aware — a watch launched wrong must still produce a wake event (stderr never reaches the event stream). Replace `err()` and add the mirror to `usage()` (`cmd` is parsed at line 60, but `usage` can fire from line 88 where `cmd` is set, and `err` only fires after that too; guard with `${cmd:-}` anyway):

```bash
usage() {
  if [ "${cmd:-}" = "watch" ]; then
    echo "sprint-mail: bad or missing arguments — usage: sprint-mail.sh watch <sprint-dir> <name-or-glob(s)> [<timeout-seconds>]"
  fi
  cat >&2 <<'EOF'
... (existing heredoc unchanged, plus the new watch line) ...
EOF
  exit 2
}
err() {
  echo "sprint-mail: $1" >&2
  if [ "${cmd:-}" = "watch" ]; then echo "sprint-mail: $1"; fi
  exit 2
}
```

(Use the if-form, not `[ … ] && echo` — under `set -e` a false `&&` chain would exit with the wrong status.)

(c) Replace the header paragraph that starts `# \`arm --harness codex|claude\` registers a reactive wait` (lines 23-30) with:

```bash
# `arm --harness codex` registers a reactive wait for the Codex Stop hook
# (codex-stop-wait.sh): one record per worktree under $MAIL_ROOT/.codex-waits/,
# four lines — worktree root, absolute glob(s), timeout, absolute cursor path.
# `--harness` requires the hook's Stop reference to already exist (a reference
# is not proof the hook is active — installers own that). `disarm` removes this
# worktree's record. Claude sessions do not arm — the Claude wait is `watch`,
# launched as a harness background task (Monitor): a cursor-aware poll that
# prints exactly ONE stdout line (new mail, timeout guidance, or error — errors
# mirrored to stderr) and exits; one watch per worktree via an advisory lock in
# <mail_dir>/.watch/ (stale when its PID is dead or its age passes 2x timeout).
# Kimi sessions wait via recurring cron sweeps (see sprint-orchestrator/SKILL.md
# 'Supervising the Wave').
```

(NOTE: `arm` still ACCEPTS claude until Task 3 — this comment lands with Task 1 because it describes watch; the lint pin flips for arm strings happen in Task 3 with the behavior.)

(d) Add helpers directly after `cursor_file()`:

```bash
watch_lock() {  # advisory one-watch-per-worktree lock, keyed like the cursor
  printf '%s\n' "$mail_dir/.watch/$(printf '%s\n' "$consumer" | cksum | cut -d' ' -f1)"
}
watch_lock_stale() {  # $1=lock — stale when its PID is dead (fast path; a killed
  # watch cannot rm its own lock) or past 2x its recorded timeout (backstop for
  # PID reuse). Lock format: line 1 PID, line 2 timeout.
  local pid lt age
  pid="$(sed -n 1p "$1" 2>/dev/null)"
  case "$pid" in ''|*[!0-9]*) return 0 ;; esac   # malformed → stale
  kill -0 "$pid" 2>/dev/null || return 0
  lt="$(sed -n 2p "$1" 2>/dev/null)"; case "$lt" in ''|*[!0-9]*) lt=1800 ;; esac
  age=$(( $(date +%s) - $(stat -f %m "$1" 2>/dev/null || echo 0) ))
  [ "$age" -gt $(( lt * 2 )) ]
}
```

(e) Add the `watch)` case directly after the `wait)` case. All failures go through the (now mirroring) `err`:

```bash
  watch)
    # Background wait for Claude sessions: the harness launcher turns stdout
    # into the wake event, so every terminal outcome is exactly ONE stdout line.
    pat="${3:-}"; timeout="${4:-1800}"
    [ -n "$pat" ] || usage
    [ -n "$consumer" ] || err "not inside a git worktree — mailbox watches are keyed per worktree; run from the project worktree"
    echo "$timeout" | grep -qE '^[0-9]+$' || err "timeout must be whole seconds (got: $timeout)"
    case "$pat" in
      */*|*$'\n'*) err "pattern is a mail filename or glob, not a path (got: $pat)" ;;
    esac
    mkdir -p "$mail_dir/.watch"
    lock="$(watch_lock)"
    if [ -f "$lock" ] && watch_lock_stale "$lock"; then rm -f "$lock"; fi
    if ! (set -C; printf '%s\n%s\n' "$$" "$timeout" > "$lock") 2>/dev/null; then
      err "a watch is already running for this worktree ($lock) — one watch per worktree; if its process is dead the next watch will prune it, or remove the lock by hand"
    fi
    trap 'rm -f "$lock"' EXIT
    cur="$(cursor_file)"
    elapsed=0
    found=""
    while :; do
      # same predicate as `unread`: glob match minus the read-cursor
      for f in $(ls -tr "$mail_dir" 2>/dev/null); do
        matched=0
        set -f
        for p in $pat; do case "$f" in $p) matched=1; break ;; esac; done
        set +f
        [ "$matched" = 1 ] || continue
        grep -qxF "$f" "$cur" 2>/dev/null && continue
        found="${found}${found:+ }$mail_dir/$f"
      done
      [ -n "$found" ] && break
      [ "$elapsed" -ge "$timeout" ] && break
      sleep "$POLL"; elapsed=$((elapsed + POLL))
    done
    if [ -n "$found" ]; then
      printf 'New sprint mail arrived: %s — a nudge, not state: sweep with sprint-mail.sh unread, mark seen, and act on what the SWEEP returns. Supervisors: re-park (sprint-mail.sh supervise) before ending the turn if the wave is still running.\n' "$found"
      exit 0
    fi
    case "$pat" in
      *-reply.md*)
        # question-wait (also wins for combined reply+note patterns: the reply
        # is the blocking need, the note match is opportunistic)
        printf 'Mailbox watch timed out after %ss with no new mail. Executors: take the contract'\''s no-reply fallback (handback/blocked) and post your terminal concluded. Supervisors: sweep, then launch a new watch if the wave is still running.\n' "$timeout" ;;
      *-note.md*)
        # dependency park — expiring is not a verdict on the gate
        printf 'Mailbox watch timed out after %ss with no new mail. This was a dependency park on a gate note — the gate is still closed. Launch the same watch again and keep parking; do NOT post a terminal concluded merely because the wait expired. Take the handback path only if the dependency'\''s premise changed.\n' "$timeout" ;;
      *-question.md*|*-concluded.md*)
        # supervisor sweep form
        printf 'Mailbox watch timed out after %ss with no new mail. Supervisors: sweep ALL new mail with sprint-mail.sh unread, then launch a new watch (sprint-mail.sh supervise --harness claude) before ending the turn if the wave is still running.\n' "$timeout" ;;
      *)
        printf 'Mailbox watch timed out after %ss with no new mail. Executors: take the contract'\''s no-reply fallback (handback/blocked) and post your terminal concluded. Supervisors: sweep, then launch a new watch if the wave is still running.\n' "$timeout" ;;
    esac
    exit 1
    ;;
```

- [ ] **Step 4: Run the mailbox suite**

Run: `sprint-orchestrator/test/test-sprint-mail.sh > "$TMP_OUT" 2>&1; echo "exit=$?"; grep -c '^FAIL' "$TMP_OUT"`
Expected: `exit=0`, `0` FAILs (old and new cases).

- [ ] **Step 5: Run the lint**

Run: `test/lint-skills.sh > "$TMP_OUT" 2>&1; echo "exit=$?"; tail -2 "$TMP_OUT"`
Expected: `exit=0`. Task 1 touches no pinned strings — the pinned `arm` usage/refusal strings and `"Kimi has no Stop-hook wait"` all survive (the kimi refusal message at line 80 is untouched).

- [ ] **Step 6: Commit**

```bash
git branch --show-current && git status --short
git add sprint-orchestrator/sprint-mail.sh sprint-orchestrator/test/test-sprint-mail.sh
git commit -m "feat(sprint-orchestrator): add sprint-mail watch — cursor-aware background wait"
```

---

### Task 2: Phase 0 transport probe (Monitor-primary confirmation)

**Files:**
- Create: `docs/superpowers/plans/2026-07-23-phase0-probe-results.md` (findings record)
- No production code changes.

**Interfaces:**
- Consumes: `sprint-mail.sh watch` from Task 1.
- Produces: confirmation (or refutation) of the Monitor-primary decision, plus the EXACT permission rule for unattended re-arm — Task 6 inserts that rule into REFERENCE.md verbatim. **Decision rule (spec, revised after the online evidence pass): Monitor is primary if it passes idle re-invocation and unattended re-arm; Bash `run_in_background` is the fallback, not a peer.** Sourced evidence already on file (recorded in the spec's review addendum): Monitor's wake is documented as a model-visible transcript event (v2.1.98 notes); Bash background shells have a documented idle-session memory-pressure reaper (v2.1.193) and adverse longevity reports (#76974, #80372). The probe CONFIRMS locally; it no longer selects between peers.

The rendered-instruction variants (Tasks 3-6 are written with the Monitor-primary form, which embeds the Bash fallback clause inline — if the probe REFUTES Monitor, swap primary and fallback in those strings and record why):

- **Primary:** ``start the mailbox watch as a Monitor (persistent: true, description: "sprint mailbox")`` + inline clause ``(no Monitor tool in this session? launch the same command with Bash run_in_background: true)``
- **Refuted-Monitor fallback:** ``launch the mailbox watch as a background task (Bash tool, run_in_background: true)``

This task runs in a live interactive Claude Code session. External writers must be `nohup`-detached so they survive the tool call that spawns them. Use a scratch repo so no real mailbox is touched.

- [ ] **Step 1: Fixture**

```bash
P=/private/tmp/claude-501/-Users-rkuprin-claude-skills/512b58b1-5272-4522-8203-4c547172bfe9/scratchpad/probe
mkdir -p "$P/repo" && git -C "$P/repo" init -q
export SM=/Users/rkuprin/claude-skills/sprint-orchestrator/sprint-mail.sh
# All probe commands run: cd "$P/repo" with SPRINT_MAIL_ROOT="$P/mailroot" SPRINT_MAIL_POLL=2
```

- [ ] **Step 2: Monitor — idle wake + turn count.** Detach a writer that posts mail at +60s, start the Monitor, END THE TURN, operator stays idle:

```bash
cd "$P/repo" && nohup sh -c 'sleep 60; printf "probe mail\n" | SPRINT_MAIL_ROOT="'"$P"'/mailroot" '"$SM"' post docs/sprints/probe 01 evidence -' >/dev/null 2>&1 &
# then: Monitor(command: "cd $P/repo && SPRINT_MAIL_ROOT=$P/mailroot SPRINT_MAIL_POLL=2 $SM watch docs/sprints/probe '01-*-evidence.md' 300", description: "sprint mailbox probe", persistent: true)
```

Record: did the event re-invoke the model with no operator input? Latency from script exit to wake? **Turn count** — our watch emits its line and exits immediately after; does that produce ONE wake or two (line event + completion notification)? Duplicates are tolerable (the sweep dedups) but must be known.

- [ ] **Step 3: Monitor — timeout + unattended re-arm.** Watch with timeout 30, no writer. When the timeout guidance wakes the session, IMMEDIATELY re-launch the same Monitor in that continuation with NO operator action. Record: guidance line delivered? Re-launch without a permission prompt? Write down the EXACT allow rule in force (or added) — per the docs, Monitor uses Bash permission rules, so an exact-command rule should cover both launchers; verify the rule matches the command form actually rendered (direct script path, not `bash <path>`).

- [ ] **Step 4: Bash `run_in_background` — same two experiments** (fallback validation, not preference): idle wake on exit, turn behavior, unattended re-launch.

- [ ] **Step 5: Lifecycle edges (Monitor).** Record lockfile + task state for: Esc pressed mid-turn after launch; session closed and resumed (`claude -r` — docs say monitors are NEVER restored on resume; verify the orphan notice behavior and that re-parking after the sweep works); mail landing while the model is mid-turn (start a watch, keep doing tool work, writer posts during it — when does the event arrive?); three near-simultaneous completions (three watches on disjoint globs, one writer satisfying all — batching/loss?). Verify a dead-PID lock is pruned on the next `watch` launch.

- [ ] **Step 6: Longevity soft-check.** Start a Monitor watch with timeout 10800 and leave it running for the remainder of implementation (≥1h); verify at Task 8 it is alive or delivered. Full 3h evidence may come from the first production wave — record as residual if not proven here. **Use a dedicated sprint dir (`docs/sprints/probe-longevity`) so Task 8's smoke never contends with this watch's lock.**

- [ ] **Step 7: Write `docs/superpowers/plans/2026-07-23-phase0-probe-results.md`** — per experiment: observed behavior, timing, turn counts, the exact permission rule, the confirmed launcher decision, residuals. Acceptance criterion (from the evidence pass): the park **eventually drains the durable mailbox without polling or blocking the previous turn** — not "every wake arrives promptly exactly once". If BOTH Monitor and Bash fail idle re-invocation: STOP — return to the spec's fallback (shorter budgets) and re-plan; do not proceed to Task 3.

- [ ] **Step 8: Commit**

```bash
git add docs/superpowers/plans/2026-07-23-phase0-probe-results.md
git commit -m "docs(sprint-orchestrator): record Phase 0 watch-transport probe results"
```

---

### Task 3: `supervise --harness claude` prints the watch park; `arm` refuses claude

**Files:**
- Modify: `sprint-orchestrator/sprint-mail.sh` (pre-dispatch harness case ~lines 66-86, `arm)` body ~lines 226-272, `supervise)` ~lines 273-308, usage lines for `arm`)
- Modify: `sprint-orchestrator/test/test-sprint-mail.sh` (claude-arm fixture block ~lines 128-145 AND the record-based `supervise: claude budget is 10800` block ~lines 317-321)
- Modify: `test/lint-skills.sh` (SMAIL pins ~lines 376-388)

**Interfaces:**
- Consumes: `watch_lock()`, `watch_lock_stale()` from Task 1; the Monitor-primary instruction form from Task 2.
- Produces: `supervise --harness claude <sprint-dir>` prints the park instruction (or `already watching: <lock>`); `arm --harness claude` exits 2 redirecting to the watch. Tasks 4-6 quote these behaviors in prose.

- [ ] **Step 1: Update the tests.** Three edits in `test-sprint-mail.sh`:

(1) Replace the claude-arm block IN PLACE (~lines 128-145: the fixture that fakes a wired `CLAUDE_CONFIG_DIR` and asserts `arm --harness claude proceeds`, plus the dependent "arm --harness codex still refuses when only Claude is wired" case). The replacement must stay hermetic at the RED stage too — on this machine the real `~/.claude/settings.json` has the hook wired, so without an isolated empty config the OLD code would arm successfully and leak a record into later cases. Point `CLAUDE_CONFIG_DIR` at an empty fixture and disarm unconditionally after:

```bash
# ---- arm refuses claude: the Claude wait is a background watch ----
mkdir -p "$TMP/claude-none"
out="$(CLAUDE_CONFIG_DIR="$TMP/claude-none" "$SUT" arm --harness claude "$SPRINT" "07-011-reply.md" 900 2>&1)"; rc=$?
"$SUT" disarm "$SPRINT"   # hermetic either way: red leaves a record or a refusal leaves none
[ "$rc" != 0 ] && echo "$out" | grep -q "background watch" \
  && ok "arm --harness claude refused, redirects to watch" \
  || no "arm --harness claude refused, redirects to watch (rc=$rc out=$out)"
```

(2) Replace the record-based supervise block at ~lines 317-321 (`# ---- supervise: claude budget is 10800 ----` … `"$SUT" disarm "$SPRINT"`) — after this task `supervise --harness claude` writes no record, so that test would fail forever. Replacement (uses `$SPRINT`/`$MDIR`, both in scope there):

```bash
# ---- supervise claude: prints the watch park (no record), idempotent via lock ----
WLOCK_S="$MDIR/.watch/$(printf '%s\n' "$(cd "$REPO_A" && pwd -P)" | cksum | cut -d' ' -f1)"
out="$(SPRINT_MAIL_ASSUME_HARNESS=none "$SUT" supervise --harness claude "$SPRINT")"; rc=$?
[ "$rc" = 0 ] && echo "$out" | grep -q "watch '$SPRINT'" && echo "$out" | grep -q "10800" \
  && ok "supervise claude prints the watch park with the idle budget" \
  || no "supervise claude prints the watch park (rc=$rc out=$out)"
echo "$out" | grep -q "Monitor" \
  && ok "supervise claude names the Monitor launcher" || no "supervise claude names the Monitor launcher (got: $out)"
echo "$out" | grep -q "run_in_background" \
  && ok "supervise claude carries the bash fallback clause" || no "supervise claude carries the bash fallback clause"
echo "$out" | grep -q "END YOUR TURN" \
  && ok "supervise claude ends the turn" || no "supervise claude ends the turn"
[ -z "$(ls "$WAITS"/wait-* 2>/dev/null)" ] \
  && ok "supervise claude writes no wait record" || no "supervise claude writes no wait record"
mkdir -p "$MDIR/.watch"
printf '%s\n10800\n' "$$" > "$WLOCK_S"
out="$(SPRINT_MAIL_ASSUME_HARNESS=none "$SUT" supervise --harness claude "$SPRINT")"; rc=$?
[ "$rc" = 0 ] && echo "$out" | grep -q "already watching" \
  && ok "supervise claude is idempotent under a fresh live lock" \
  || no "supervise claude is idempotent under a fresh live lock (rc=$rc out=$out)"
rm -f "$WLOCK_S"
```

(3) No other codex arm/supervise cases change — verify the stale-sweep regression block right below still passes untouched.

- [ ] **Step 2: Run to verify the new cases fail**

Run: `sprint-orchestrator/test/test-sprint-mail.sh > "$TMP_OUT" 2>&1; echo "exit=$?"; grep '^FAIL' "$TMP_OUT"`
Expected: nonzero exit; the refusal + supervise-claude cases FAIL (old code arms records and execs arm); everything else passes.

- [ ] **Step 3: Implement.** In `sprint-mail.sh`:

(a) Pre-dispatch case (~line 77): arm now accepts only codex —

```bash
    else
      case "$harness" in
        codex) ;;
        claude) err "arm refuses claude — the Claude wait is a background watch, not a Stop hook: run 'sprint-mail.sh supervise --harness claude' for the park instruction, or launch 'sprint-mail.sh watch' as a background task per the kickoff's Mailbox wait line" ;;
        kimi) err "arm refuses kimi — Kimi has no Stop-hook wait; a Kimi session waits via a recurring cron sweep (see the kickoff's Mailbox wait line or sprint-orchestrator/SKILL.md 'Supervising the Wave')" ;;
        *) err "arm --harness needs 'codex' (got: ${harness:-<empty>})" ;;
      esac
    fi
```

Also line 70's shared message: change `--harness <codex|claude>` to `--harness` (it serves both arm and supervise; keep the "requires --harness" phrasing — a test greps it).

(b) `arm)` body: line 229 message becomes `arm requires --harness <codex> immediately after 'arm' …`; the hook-reference `case "$harness"` (~lines 237-246) loses its `claude)` branch — only the codex `hooks.json` check remains (as a plain statement, no case needed).

(c) `supervise)`: split the shared `codex|claude)` branch. `codex)` keeps today's body with `budget=1800` fixed (drop the `[ "$harness" = "claude" ] && budget=10800` line). Add:

```bash
      claude)
        globs='*-question.md *-concluded.md'
        lock="$(watch_lock)"
        if [ -f "$lock" ] && ! watch_lock_stale "$lock"; then
          printf 'already watching: %s\n' "$lock"
          exit 0
        fi
        cat <<EOF
Claude supervisor park for $sprint_dir — the wait is a background watch: the turn ends, the operator keeps the prompt, the watch's event wakes you. Do this now:

1. Start the mailbox watch as a Monitor (persistent: true, description: "sprint mailbox"):
   command: '$0' watch '$sprint_dir' '$globs' 10800
   (No Monitor tool in this session? Launch the same command with the Bash tool, run_in_background: true.)
2. END YOUR TURN. The wake event carries the new-mail line or the timeout guidance — a nudge, never state: sweep first (sprint-mail.sh unread, then seen), act on what the sweep returns, then run 'sprint-mail.sh supervise --harness claude' again if the wave is still running.
3. One watch per worktree — if this printed 'already watching', do not launch another. Monitors are never restored on session resume: no live watch after a resume means sweep, then re-park.
EOF
        ;;
```

(d) usage/header: `arm --harness <codex|claude>` → `arm --harness <codex>` in the top comment (line 7) and `usage()` (line 50).

- [ ] **Step 4: Run the suite**

Run: `sprint-orchestrator/test/test-sprint-mail.sh > "$TMP_OUT" 2>&1; echo "exit=$?"; grep -c '^FAIL' "$TMP_OUT"`
Expected: `exit=0`, `0`.

- [ ] **Step 5: Update lint pins in the same commit.** In `test/lint-skills.sh`:

- `has "mail: arm usage line" "arm --harness <codex|claude> <sprint-dir> <name-or-glob(s)>"` → `"arm --harness <codex> <sprint-dir> <name-or-glob(s)>"`.
- Replace `has "mail: arm claude branch names installer" "install-claude-hook.sh" "$SMAIL"` with `has "mail: arm refuses claude with redirect" "background watch, not a Stop hook" "$SMAIL"`.
- Add after it:
  ```bash
  has   "mail: watch usage line"                  "watch <sprint-dir> <name-or-glob(s)>" "$SMAIL"
  has   "mail: watch one-line protocol"           "exactly ONE stdout line" "$SMAIL"
  has   "mail: claude park is a Monitor"          "as a Monitor (persistent: true" "$SMAIL"
  has   "mail: claude park carries bash fallback" "run_in_background: true" "$SMAIL"
  has   "mail: wake is a nudge"                   "a nudge, never state" "$SMAIL"
  ```
- LEAVE lint line 124 (`reference: claude re-arm at idle budget` → REFERENCE.md) untouched — REFERENCE.md keeps the old prose until Task 6; the pin still passes.

Run: `test/lint-skills.sh > "$TMP_OUT" 2>&1; echo "exit=$?"; tail -2 "$TMP_OUT"` — Expected: `exit=0`.

- [ ] **Step 6: Commit**

```bash
git branch --show-current && git status --short
git add sprint-orchestrator/sprint-mail.sh sprint-orchestrator/test/test-sprint-mail.sh test/lint-skills.sh
git commit -m "feat(sprint-orchestrator): claude parks via background watch — arm refuses, supervise prints the park"
```

---

### Task 4: `wave-handoffs.sh` renders the claude watch wait

**Files:**
- Modify: `sprint-orchestrator/wave-handoffs.sh` (the claude `mailwait` string, ~line 232-233)
- Modify: `sprint-orchestrator/test/test-wave-handoffs.sh` (claude assertion ~line 84 AND the stale `no background-task wait rendered` case at ~lines 85-87)
- Modify: `test/lint-skills.sh` (renderer pins ~lines 345 and ~352)

**Interfaces:**
- Consumes: the Monitor-primary instruction form; `watch` CLI shape from Task 1.
- Produces: claude-target kickoffs carry the watch-based `Mailbox wait:` line quoted below; Task 5 mirrors the same form in agent-handoff.

- [ ] **Step 1: Update the tests.** In `test-wave-handoffs.sh`:

(1) Replace the line-84 claude assertion with:

```bash
has "claude story renders watch wait line"  "$OUTPUT" "\`~/.claude/skills/sprint-orchestrator/sprint-mail.sh watch '$SPRINT' '08-{SSS}-reply.md' 1800\`"
has "claude watch line is a Monitor"        "$OUTPUT" "as a Monitor (persistent: true"
has "claude watch line carries bash fallback" "$OUTPUT" "run_in_background: true"
```

(Note the single quotes around `'$SPRINT'` INSIDE the double-quoted needle — the rendered command single-quotes the sprint dir and the glob; the `~/` script path stays unquoted so the shell expands it.)

(2) DELETE the stale negative case at ~lines 85-87 (`case "$OUTPUT" in *'as a background task'*) no "no background-task wait rendered" …`) — the invariant it guarded (no orphaned `nohup`-style waits) is now covered by the positive Monitor assertions plus the surviving `under \`nohup\`` pins; keeping a ban that the new design legitimately violates in spirit would be a lint that lies.

(3) Keep the codex assertions at lines 82-83 byte-identical.

- [ ] **Step 2: Run to verify it fails**

Run: `sprint-orchestrator/test/test-wave-handoffs.sh > "$TMP_OUT" 2>&1; echo "exit=$?"; grep '^FAIL' "$TMP_OUT"`
Expected: nonzero exit; the three new claude assertions FAIL.

- [ ] **Step 3: Implement.** In `wave-handoffs.sh`, replace the `*)` (claude) `mailwait` assignment (~line 233) with:

```bash
    *)     contract="~/.claude/skills/agent-handoff/EXECUTION.md"
           mailwait='post your question, then start the mailbox watch as a Monitor (persistent: true, description: "sprint mailbox") — command: `~/.claude/skills/sprint-orchestrator/sprint-mail.sh watch '"'"''"$sprint_dir"''"'"' '"'"''"$story"'-{SSS}-reply.md'"'"' 1800` (SSS = your question'"'"'s sequence; no Monitor tool in this session? launch the same command with Bash run_in_background: true) — and END YOUR TURN: the watch'"'"'s event wakes you with the reply or the timeout guidance; the operator keeps the prompt. The wake line is a nudge, never state — on any wake, or on finding you have no live watch (monitors are never restored on resume), sweep unread reply mail first (sprint-mail.sh unread), then re-launch only if still waiting. Never foreground the wait.' ;;
```

(The quoting renders ``watch '<sprint-dir>' '<NN>-{SSS}-reply.md' 1800`` — verified expansion shape; run the renderer once and eyeball the line before committing.)

- [ ] **Step 4: Run the suite**

Run: `sprint-orchestrator/test/test-wave-handoffs.sh > "$TMP_OUT" 2>&1; echo "exit=$?"; grep -c '^FAIL' "$TMP_OUT"`
Expected: `exit=0`, `0`.

- [ ] **Step 5: Update the lint pins (same commit).**

- Replace `has "renderer: claude arm carries --harness" "arm --harness claude" "$WHS"` with `has "renderer: claude wait is the background watch" "sprint-mail.sh watch" "$WHS"`.
- DELETE `hasnt "renderer: no background-task wait" "as a background task" "$WHS"` (~line 352) — same rationale as the wave-test case: the new claude string legitimately describes a harness background task; the orphaned-wait ban lives on in the `nohup` pins.

Run: `test/lint-skills.sh > "$TMP_OUT" 2>&1; echo "exit=$?"; tail -2 "$TMP_OUT"` — Expected: `exit=0`.

- [ ] **Step 6: Commit**

```bash
git add sprint-orchestrator/wave-handoffs.sh sprint-orchestrator/test/test-wave-handoffs.sh test/lint-skills.sh
git commit -m "feat(sprint-orchestrator): render claude mailbox wait as background watch"
```

---

### Task 5: agent-handoff contract carries the watch form

**Files:**
- Modify: `agent-handoff/EXECUTION.md` (claude branch, ~lines 141-143)
- Modify: `agent-handoff/SKILL.md` (~line 172-173 and the claude segment of the line-199 template)
- Modify: `test/lint-skills.sh` (pins ~lines 239, 242, 289, 294)

**Interfaces:**
- Consumes: the exact `Mailbox wait:` claude string from Task 4 (contract and renderer must agree).
- Produces: executor-facing prose for Claude waits; no code.

- [ ] **Step 1: `EXECUTION.md`.** Replace the claude bullet (lines 141-143) with:

```markdown
  - Claude, MAIN session only: start the mailbox watch as a Monitor (persistent: true,
    description: "sprint mailbox") — command:
    `sprint-mail.sh watch <sprint-dir> '{NN}-{SSS}-reply.md' 1800` — then END YOUR TURN
    with a one-line status. (No Monitor tool in this session? Launch the same command with
    the Bash tool, run_in_background: true.) The watch's event wakes you with the reply or
    the timeout guidance; the operator keeps the prompt. The wake line is a nudge, never
    state: on any wake, or on finding you have no live watch (monitors are never restored
    on resume), sweep unread reply mail first (`sprint-mail.sh unread`), then re-launch
    only if still waiting. Never foreground the watch, and never `arm` — Claude has no
    Stop-hook wait.
```

- [ ] **Step 2: `SKILL.md`.** At ~line 172-173, replace `Claude targets (claude-cli, claude-session) render the claude arm-and-end-turn form (`arm --harness claude …`)` with `Claude targets (claude-cli, claude-session) render the claude background-watch form (`sprint-mail.sh watch …` as a Monitor, bash-fallback clause included)`. In the line-199 template, replace the claude segment (between the first and second `|`) with:

```
post your question, then start the mailbox watch as a Monitor (persistent: true, description: "sprint mailbox") — command: `~/.claude/skills/sprint-orchestrator/sprint-mail.sh watch '{SPRINT_DIR}' '{NN}-{SSS}-reply.md' 1800` (SSS = your question's sequence; no Monitor tool in this session? launch the same command with Bash run_in_background: true) — and END YOUR TURN: the watch's event wakes you with the reply or the timeout guidance; the operator keeps the prompt. The wake line is a nudge, never state — on any wake, or on finding you have no live watch (monitors are never restored on resume), sweep unread reply mail first (sprint-mail.sh unread), then re-launch only if still waiting. Never foreground the wait.
```

- [ ] **Step 3: Update lint pins (same commit).**

- Replace line 239's `has "handoff: claude wait form is arm-and-end-turn" "arm --harness claude {SPRINT_DIR} {NN}-{SSS}-reply.md 1800" "$AH"` with `has "handoff: claude wait form is the background watch" "sprint-mail.sh watch '{SPRINT_DIR}' '{NN}-{SSS}-reply.md' 1800" "$AH"` (needle matches the quoted template exactly).
- DELETE `hasnt "handoff: no background-task wait" "as a background task" "$AH"` (~line 242) — inverted by the new design; the orphaned-wait ban survives as the `nohup` pin.
- Replace line 289's `has "contract: claude main-session arm wait" …` with `has "contract: claude main-session watch wait" "sprint-mail.sh watch <sprint-dir> '{NN}-{SSS}-reply.md' 1800" "$AHEXEC"`.
- DELETE `hasnt "contract: no background-task wait" "as a background task" "$AHEXEC"` (~line 294) — same rationale. The neighboring pins `"Arming and ending the turn IS the wait"` (codex bullet) and `"the Stop hook never fires for a subagent"` (subagent bullet) and the `nohup` ban all still pass — verify, do not touch those bullets.

- [ ] **Step 4: Run lint + adjacent suites**

Run: `test/lint-skills.sh > "$TMP_OUT" 2>&1; echo "lint=$?"; sprint-orchestrator/test/test-wave-handoffs.sh > /dev/null 2>&1; echo "wh=$?"`
Expected: `lint=0`, `wh=0`.

- [ ] **Step 5: Commit**

```bash
git add agent-handoff/EXECUTION.md agent-handoff/SKILL.md test/lint-skills.sh
git commit -m "docs(agent-handoff): claude wait form is the background watch"
```

---

### Task 6: sprint-orchestrator prose — REFERENCE.md + README.md

**Files:**
- Modify: `sprint-orchestrator/REFERENCE.md` (Claude bullet lines 145-149; subagent sentence lines 187-194)
- Modify: `sprint-orchestrator/README.md` ("Reactive waits on Claude" section lines 222-250; the parallel-hook note relocation; subagent sentence ~line 169)
- Modify: `test/lint-skills.sh` (pins: line 124; sprint-readme block ~lines 397-408)
- Check-only: `sprint-orchestrator/SKILL.md` (grep, expect no hits)

**Interfaces:**
- Consumes: park instruction wording from Task 3; the EXACT permission rule from Task 2's probe results doc.
- Produces: operator/supervisor-facing prose; the "Mailbox mechanics" Claude bullet Tasks 7-8 verify against.

- [ ] **Step 1: REFERENCE.md Claude bullet** (lines 145-149) becomes (insert the exact allow rule recorded in `2026-07-23-phase0-probe-results.md` where marked):

```markdown
- **Claude**: supervise prints the watch park — start
  `sprint-mail.sh watch <sprint-dir> '*-question.md *-concluded.md' 10800` as a Monitor
  (persistent: true; no Monitor tool → the same command via Bash `run_in_background:
  true`) and end the turn; the watch's event wakes the session, and the operator keeps
  the prompt throughout. Nothing to install. The wake line is a nudge, never state —
  sweep before acting. One watch per worktree (advisory lock with PID-liveness;
  `supervise` prints `already watching` instead of a duplicate park). Monitors are never
  restored on session resume: no live watch means sweep, then re-park. The session's
  permission posture must let the watch launch unattended — the allow rule on this
  machine is `<EXACT RULE FROM THE PROBE RESULTS DOC>`; a permission prompt at re-park
  time kills reactive supervision. Main sessions only.
```

- [ ] **Step 2: REFERENCE.md subagent sentence** (~line 189): replace `a subagent never arms a blocking mailbox wait — the Stop hook never fires for it, on any harness — so its` with `a subagent never parks on a mailbox wait — no wake can reach it after it returns, on any harness — so its`.

- [ ] **Step 3: README.md "Reactive waits on Claude"** (lines 222-250) — replace the whole section with:

```markdown
### Reactive waits on Claude — nothing to install (main sessions)

A main-session Claude supervisor or executor waits by starting the mailbox watch as a
background task and ending its turn: `sprint-mail.sh watch <sprint-dir>
<reply-file-or-globs> [<timeout>]` as a Monitor (persistent: true; sessions without the
Monitor tool launch the same command via Bash `run_in_background: true` — supervise
prints the exact park). The watch polls the mailbox against the worktree's read-cursor
and exits with ONE line — the new-mail wake or the timeout guidance — and that event
wakes the session. The operator keeps the prompt the whole time; there is no Stop hook,
no arm record, and nothing to install (Monitor ships with Claude Code since v2.1.98).
The wake line is a nudge, never state: the woken session sweeps (`unread`/`seen`) before
acting. One watch per worktree, enforced by an advisory lock under the mailbox's
`.watch/` dir (stale when its PID is dead or its age passes 2x its timeout). Monitors
are never restored on session resume — no live watch means sweep, then re-park.
Budgets: 10800 for the supervisor idle sweep, 1800 for targeted reply waits. The
session's permission posture must allow the watch command to launch unattended —
re-parking after a wake happens with no operator present. Main sessions only: an
in-session subagent cannot be woken after it returns, so rendered subagent kickoffs
carry the non-arming fallback.

Machines that ran the retired `install-claude-hook.sh`: delete the `claude-stop-wait.sh`
Stop group from `~/.claude/settings.json` (leave co-installed Stop hooks untouched) —
the hook and installer no longer exist in this repo, and a settings entry pointing at a
deleted file errors on every Stop.
```

Also: (a) update ~line 169's subagent rationale to the "no wake can reach a returned subagent" wording; (b) the "holds the Stop event's completion" sentence (old lines 248-249) applies to the CODEX hook and its lint pin stays — MOVE the sentence into the "Reactive waits on Codex" section if it is not already stated there, so the pin keeps guarding a real sentence; (c) update the intro mention at ~line 227 if it names `install-claude-hook.sh`.

- [ ] **Step 4: Update lint pins (same commit).**

- Line 124: `has "reference: claude re-arm at idle budget" "arm --harness claude <sprint-dir> '*-question.md *-concluded.md' 10800" "$ORCH_REF"` → `has "reference: claude watch at idle budget" "watch <sprint-dir> '*-question.md *-concluded.md' 10800" "$ORCH_REF"`.
- Sprint-readme block: drop `has "sprint readme: names the claude installer" …`, `has "sprint readme: claude arm carries --harness" …`, `has "sprint readme: claude budget note" "timeout: 10860" …`. Keep `has "sprint readme: parallel-hook note" "holds the Stop event's completion" …` (sentence relocated to the Codex section per Step 3b).
- Add:
  ```bash
  has   "sprint readme: claude waits need no install" "Reactive waits on Claude — nothing to install" "$ORCH_README"
  has   "sprint readme: claude migration note"        "delete the \`claude-stop-wait.sh\` Stop group" "$ORCH_README"
  has   "reference: claude unattended permission rule" "launch unattended" "$ORCH_REF"
  has   "reference: wake is a nudge"                   "a nudge, never state" "$ORCH_REF"
  ```

- [ ] **Step 5: SKILL.md check.** Run: `grep -n "arm --harness claude\|claude-stop-wait\|install-claude-hook\|Stop hook" sprint-orchestrator/SKILL.md` — expected: no hits. If a hit appears, update only that sentence to the watch wording.

- [ ] **Step 6: Run lint**

Run: `test/lint-skills.sh > "$TMP_OUT" 2>&1; echo "exit=$?"; tail -2 "$TMP_OUT"`
Expected: `exit=0`.

- [ ] **Step 7: Commit**

```bash
git add sprint-orchestrator/REFERENCE.md sprint-orchestrator/README.md test/lint-skills.sh
git commit -m "docs(sprint-orchestrator): rewrite Claude reactive-wait prose for the watch park"
```

---

### Task 7: Retire the Claude hook — ordered migration, deletions, root docs

**Files:**
- Modify: `~/.claude/settings.json` (remove ONE Stop group — machine state, not repo)
- Delete: `sprint-orchestrator/claude-stop-wait.sh`, `sprint-orchestrator/install-claude-hook.sh`, `sprint-orchestrator/test/test-claude-stop-wait.sh`, `sprint-orchestrator/test/test-install-claude-hook.sh`
- Modify: `sprint-orchestrator/codex-stop-wait.sh` (header only), `sprint-orchestrator/README.md` (test list ~lines 296-306), root `README.md` (~lines 48-52 and 77-80), `INSTALL.md` (intro line ~36, Claude block ~lines 48-59, verify list ~lines 71-80, report section ~lines 83-88), `test/lint-skills.sh` (claude hook/installer pins ~lines 365-375, 392-396, 410, 419-421)

**Interfaces:**
- Consumes: Task 6's completed prose (sprint docs no longer point at the installer).
- Produces: a machine with no Claude Stop hook wired and a repo with no Claude hook files; the byte-identical lint pin is gone.

**ORDER IS MANDATORY (spec "Migration"): settings edit BEFORE file deletion.**

- [ ] **Step 1: Remove the settings entry (surgical).**

```bash
python3 - "$HOME/.claude/settings.json" <<'PY'
import json, sys
path = sys.argv[1]
with open(path) as f: data = json.load(f)
groups = data.get("hooks", {}).get("Stop", [])
keep = [g for g in groups if not any("claude-stop-wait.sh" in h.get("command", "") for h in g.get("hooks", []))]
assert len(keep) == len(groups) - 1, f"expected exactly one claude-stop-wait group, found {len(groups) - len(keep)}"
data["hooks"]["Stop"] = keep
with open(path, "w") as f: json.dump(data, f, indent=2)
print(f"removed 1 Stop group; {len(keep)} kept")
PY
grep -c "claude-stop-wait" "$HOME/.claude/settings.json" || echo "clean"
grep -n "Stop" "$HOME/.claude/settings.json" | head -5
```

Expected: `removed 1 Stop group; N kept`, then `clean`, and the co-installed (iTerm-status) Stop hook still listed. (Pre-verified on this machine: two Stop groups exist, exactly one matches, and it contains only the mailbox hook.)

- [ ] **Step 2: Drain stale claude wait records — OPERATOR GATE, never inference.**

```bash
for f in "$HOME/.sprint-mail/.codex-waits"/*; do [ -f "$f" ] && echo "== $f" && cat "$f"; done
```

As of plan time three records exist (worktrees `~/hub`, `~/lead-us`, `~/710`). Records are harness-agnostic — liveness CANNOT be inferred from budget, age, or PID. ASK THE OPERATOR interactively which of those sessions are gone; run `sprint-mail.sh disarm <sprint-dir>` from each CONFIRMED-dead worktree only. Leave anything unconfirmed in place (a live Codex wait may be among them). Never `rm` the directory wholesale.

- [ ] **Step 3: Delete the files.**

```bash
git rm sprint-orchestrator/claude-stop-wait.sh sprint-orchestrator/install-claude-hook.sh \
       sprint-orchestrator/test/test-claude-stop-wait.sh sprint-orchestrator/test/test-install-claude-hook.sh
```

- [ ] **Step 4: `codex-stop-wait.sh` header.** Remove the byte-identical claim: in its header comment, replace the paragraph mentioning `claude-stop-wait.sh` / "BYTE-IDENTICAL" with: `# The Codex Stop hook is the only Stop-hook wait — Claude parks via 'sprint-mail.sh watch' as a background task; Kimi via cron sweeps.` Keep the body untouched.

- [ ] **Step 5: Docs that reference the deleted files.**

- `sprint-orchestrator/README.md` test list (~lines 296-306): delete the `test-claude-stop-wait.sh` and `test-install-claude-hook.sh` lines.
- Root `README.md` ~lines 48-52: the parenthetical `(including the sprint mailbox Stop hook on Codex machines)` already says Codex only — verify, leave if true. ~Lines 77-80: replace the hook sentence with: ``machine-specific setup: `sprint-orchestrator/install-codex-hook.sh` (Codex) — details in [`sprint-orchestrator/README.md`](sprint-orchestrator/README.md), "Reactive waits on Codex". Claude and Kimi need no hook — Claude waits are background watch tasks the session launches itself, Kimi waits are cron sweeps ("Reactive waits on Claude" / "on Kimi").``
- `INSTALL.md`:
  - Intro line ~36 `wire each present harness's mailbox Stop hook, once per machine` → `wire the Codex mailbox Stop hook, once per machine (Claude and Kimi need no wiring)`.
  - Replace the "Claude Code present:" block (~lines 48-59) with: `- Claude Code present: nothing to wire — Claude waits are background watch tasks the session launches itself. Details: [sprint-orchestrator/README.md](sprint-orchestrator/README.md), "Reactive waits on Claude". If ~/.claude/settings.json still carries a claude-stop-wait.sh Stop group from an earlier install, delete that group (leave other Stop hooks).`
  - Verify list (~lines 71-80): remove `test-claude-stop-wait.sh` and `test-install-claude-hook.sh`.
  - Report section (~lines 83-88): `whether each present harness's mailbox Stop hook is wired (Codex: wired **and trusted**; Claude: wired, plus any disabled-hooks warning)` → `whether the Codex mailbox Stop hook is wired **and trusted** (Claude and Kimi: nothing to wire)`.

- [ ] **Step 6: Lint pins.** In `test/lint-skills.sh`:

- Delete the CLSW block (~lines 365-369), the byte-identical diff pin (~lines 370-376), the CLINSTALLER block (~lines 392-396).
- Replace `has "repo readme: names the claude hook setup" "install-claude-hook.sh" …` with `has "repo readme: claude needs no hook" "Claude and Kimi need no hook" "$HERE/../README.md"`.
- Replace INSTALL pins ~419-421 (`wires the claude hook`, `runs the claude hook suite`, `runs the claude installer suite`) with:
  ```bash
  has   "install guide: claude needs no wiring" "nothing to wire — Claude waits are background watch tasks" "$INSTALL"
  hasnt "install guide: no claude hook installer" "./sprint-orchestrator/install-claude-hook.sh" "$INSTALL"
  hasnt "install guide: no deleted claude suites" "test-claude-stop-wait.sh" "$INSTALL"
  ```
- Add to the CSW block: `hasnt "stop-wait: codex hook is the only stop hook" "claude-stop-wait" "$CSW"`.
- Also grep the whole lint file for any remaining `claude-stop-wait` / `install-claude-hook` reference and remove it.

- [ ] **Step 7: Run everything that still exists (exit codes checked individually)**

```bash
test/lint-skills.sh > "$T/lint.out" 2>&1; echo "lint=$?"
for t in sprint-orchestrator/test/test-sprint-mail.sh sprint-orchestrator/test/test-codex-stop-wait.sh \
         sprint-orchestrator/test/test-install-codex-hook.sh sprint-orchestrator/test/test-wave-handoffs.sh \
         sprint-orchestrator/test/test-sprint-status.sh; do
  "$t" > /dev/null 2>&1; echo "$t=$?"
done
tail -2 "$T/lint.out"
```

Expected: every `=0`.

- [ ] **Step 8: Commit (explicit paths only — NOT `git add -u <dir>`)**

```bash
git branch --show-current && git status --short
git add sprint-orchestrator/claude-stop-wait.sh sprint-orchestrator/install-claude-hook.sh \
        sprint-orchestrator/test/test-claude-stop-wait.sh sprint-orchestrator/test/test-install-claude-hook.sh \
        sprint-orchestrator/codex-stop-wait.sh sprint-orchestrator/README.md \
        README.md INSTALL.md test/lint-skills.sh
git status --short   # verify ONLY the intended paths are staged
git commit -m "chore(sprint-orchestrator): retire the claude Stop hook — watch is the wait"
```

(`git add` on the four deleted paths stages their deletions — same effect as `git rm` already recorded, listed here so nothing else rides along.)

---

### Task 8: End-to-end smoke + longevity check

**Files:** none new (verification only; probe-results doc may gain a longevity line).

- [ ] **Step 1: Full suite sweep (exit codes individually)**

```bash
test/lint-skills.sh > /dev/null 2>&1; echo "lint=$?"
for t in sprint-orchestrator/test/test-*.sh; do "$t" > /dev/null 2>&1; echo "$t=$?"; done
codex/test/test.sh > /dev/null 2>&1; echo "codex=$?"
```

Expected: every `=0`.

- [ ] **Step 2: Live park smoke — on a DIFFERENT fixture sprint than Task 2's longevity watch** (its lock is per-worktree AND per-sprint-mailbox; use a second scratch repo, or first TaskStop the longevity watch and record its outcome). Run `sprint-mail.sh supervise --harness claude <fixture-sprint>` and follow its printed instruction literally: start the Monitor, end the turn, have a detached writer post a question 60s later. Verify: session woke with the one-line event, swept with `unread`/`seen`, re-parked via `supervise` (printing the park again, not `already watching`, since the first watch exited), all with zero operator input and zero permission prompts.

- [ ] **Step 3: Longevity result.** Check Task 2 Step 6's long watch: alive or cleanly delivered. Append the observation to `docs/superpowers/plans/2026-07-23-phase0-probe-results.md`; if the 3h budget remains unproven, record it as a residual to confirm on the first production wave.

- [ ] **Step 4: Commit (only if the probe doc changed)**

```bash
git add docs/superpowers/plans/2026-07-23-phase0-probe-results.md
git commit -m "docs(sprint-orchestrator): record watch longevity observation"
```
