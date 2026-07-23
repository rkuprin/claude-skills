# Claude Watch Mailbox Wait Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the blocking Claude Stop-hook mailbox wait with a background `sprint-mail.sh watch` task that wakes the session via a harness event while the operator keeps the prompt.

**Architecture:** A new cursor-aware `watch` subcommand in `sprint-mail.sh` (one atomic stdout line per terminal outcome, per-worktree lockfile) is launched as a Claude Code background task — Bash `run_in_background` or Monitor, selected by a Phase 0 probe. The Claude arm/record/Stop-hook path is retired with an ordered migration; Codex and Kimi transports are untouched.

**Tech Stack:** bash 3.2 (macOS), grep-only tests, Claude Code background-task tools. No new runtimes.

**Spec:** `docs/superpowers/specs/2026-07-23-claude-monitor-mailbox-wait-design.md` — read it before starting any task.

## Global Constraints

- bash 3.2 compatible, no `flock`, no `jq`/YAML parsers; tests are bash + grep only (repo rule).
- Every commit that changes pinned prose updates `test/lint-skills.sh` in the SAME commit.
- Watch protocol: exactly ONE stdout line per terminal outcome (wake exit 0, timeout exit 1, error exit 2 with the line mirrored to stderr). Never multiple stdout lines.
- Lock staleness convention: age > 2 × the lock's recorded timeout (mirrors `prune_stale`).
- Budgets: supervisor idle sweep 10800s, targeted reply waits 1800s. Poll: `SPRINT_MAIL_POLL`, default 20s.
- Rendered commands shell-quote the script path, sprint dir, and globs.
- Codex/Kimi wait paths must not change behavior; `.codex-waits` records are never bulk-deleted (they don't identify their harness).
- Conventional commits; stage explicit paths only; never `git add -A`.
- Default launcher in all rendered text is Bash `run_in_background` — Task 2's probe may substitute the Monitor variant (both spelled in Task 2, one substitution rule).

---

### Task 1: `sprint-mail.sh watch` subcommand

**Files:**
- Modify: `sprint-orchestrator/sprint-mail.sh` (usage lines 4-11 and 45-57, header comment lines 23-34, helpers after `cursor_file()` ~line 118, new `watch)` case after `wait)` ~line 225)
- Test: `sprint-orchestrator/test/test-sprint-mail.sh` (append before the summary block at the end)

**Interfaces:**
- Consumes: existing `cursor_file()`, `$consumer`, `$mail_dir`, `$POLL`, `usage`, `err`.
- Produces: `sprint-mail.sh watch <sprint-dir> <name-or-glob(s)> [<timeout>]` — exit 0 one wake line, exit 1 one timeout line, exit 2 one error line (mirrored to stderr); helpers `watch_lock()` (prints lock path) and `watch_lock_stale <lock>` (exit 0 if stale). Lock dir `<mail_dir>/.watch/`. Tasks 2-6 rely on these exact semantics.

- [ ] **Step 1: Write the failing tests**

Append to `sprint-orchestrator/test/test-sprint-mail.sh`, immediately before its final summary block (the `printf` of PASS/FAIL at the bottom):

```bash
# ---- watch: cursor-aware background wait — ONE stdout line per outcome ----
# Fresh sprint fixture so timeout cases see an empty mailbox.
SPRINT_W="docs/sprints/2026-07-23-watch-fixture"
WDIR="$SPRINT_MAIL_ROOT/repo-alpha/2026-07-23-watch-fixture"
WLOCK="$WDIR/.watch/$(printf '%s\n' "$(pwd -P)" | cksum | cut -d' ' -f1)"

# wake on pre-existing unread mail: immediate, one line, exit 0, lock cleaned
wq="$(printf 'which flow?\n' | "$SUT" post "$SPRINT_W" 11 question -)"
out="$("$SUT" watch "$SPRINT_W" '11-*-question.md' 20)"; rc=$?
[ "$rc" = 0 ] && ok "watch wakes on pre-existing unread mail (exit 0)" || no "watch wakes on pre-existing unread mail (rc=$rc)"
echo "$out" | grep -q "New sprint mail arrived: .*11-001-question.md" \
  && ok "watch wake line names the mail file" || no "watch wake line names the mail file (got: $out)"
[ "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" = "1" ] \
  && ok "watch wake is exactly one stdout line" || no "watch wake is exactly one stdout line"
[ ! -f "$WLOCK" ] && ok "watch removes its lock on wake" || no "watch removes its lock on wake"

# seen mail does not wake: cursor-aware timeout, reply-glob guidance, exit 1
"$SUT" seen "$SPRINT_W" 11-001-question.md
out="$("$SUT" watch "$SPRINT_W" '11-*-question.md 11-*-concluded.md' 2)"; rc=$?
[ "$rc" = 1 ] && ok "watch times out on seen-only mail (exit 1)" || no "watch times out on seen-only mail (rc=$rc)"
echo "$out" | grep -q "Mailbox watch timed out after 2s" \
  && ok "watch timeout line present" || no "watch timeout line present (got: $out)"
echo "$out" | grep -q "sweep ALL new mail" \
  && ok "question-glob timeout carries supervisor guidance" || no "question-glob timeout carries supervisor guidance (got: $out)"

# reply-glob timeout carries the executor fallback guidance
out="$("$SUT" watch "$SPRINT_W" '11-*-reply.md' 2)"
echo "$out" | grep -q "no-reply fallback" \
  && ok "reply-glob timeout carries executor guidance" || no "reply-glob timeout carries executor guidance (got: $out)"

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

# lock conflict: a fresh foreign lock refuses a second watch, line on stdout AND stderr
mkdir -p "$WDIR/.watch"
printf '99999\n1800\n' > "$WLOCK"
out="$("$SUT" watch "$SPRINT_W" '11-*-reply.md' 2 2>"$TMP/watch.err")"; rc=$?
[ "$rc" = 2 ] && echo "$out" | grep -q "already running" \
  && ok "second watch refused while lock is fresh (exit 2)" || no "second watch refused while lock is fresh (rc=$rc out=$out)"
grep -q "already running" "$TMP/watch.err" \
  && ok "watch error is mirrored to stderr" || no "watch error is mirrored to stderr"

# stale lock (older than 2x its timeout) is pruned and the watch proceeds
touch -t 202601010000 "$WLOCK"
out="$("$SUT" watch "$SPRINT_W" '11-*-reply.md' 2)"; rc=$?
[ "$rc" = 1 ] && ok "stale lock pruned, watch proceeds to timeout" || no "stale lock pruned, watch proceeds (rc=$rc out=$out)"

# watch validates like its siblings
out="$("$SUT" watch "$SPRINT_W" 'sub/dir.md' 2 2>/dev/null)"; rc=$?
[ "$rc" = 2 ] && echo "$out" | grep -q "not a path" \
  && ok "watch rejects path-shaped pattern on stdout" || no "watch rejects path-shaped pattern (rc=$rc out=$out)"
out="$("$SUT" watch "$SPRINT_W" '11-*-reply.md' soon 2>/dev/null)"; rc=$?
[ "$rc" = 2 ] && ok "watch rejects non-numeric timeout" || no "watch rejects non-numeric timeout (rc=$rc)"
```

- [ ] **Step 2: Run tests to verify the new ones fail**

Run: `sprint-orchestrator/test/test-sprint-mail.sh 2>&1 | grep -c '^FAIL'`
Expected: every new `watch` case FAILs (usage exit 2 → wrong rc/output); all pre-existing cases still pass.

- [ ] **Step 3: Implement `watch`**

In `sprint-orchestrator/sprint-mail.sh`:

(a) Add to the header usage list (after the `wait` line, both in the top comment and in `usage()`):

```
sprint-mail.sh watch <sprint-dir> <name-or-glob(s)> [<timeout-seconds>]
```

(b) Replace the header paragraph that starts `# \`arm --harness codex|claude\` registers a reactive wait` (lines 23-30) with:

```bash
# `arm --harness codex` registers a reactive wait for the Codex Stop hook
# (codex-stop-wait.sh): one record per worktree under $MAIL_ROOT/.codex-waits/,
# four lines — worktree root, absolute glob(s), timeout, absolute cursor path.
# `--harness` requires the hook's Stop reference to already exist (a reference
# is not proof the hook is active — installers own that). `disarm` removes this
# worktree's record. Claude sessions do not arm — the Claude wait is `watch`,
# launched as a harness background task: a cursor-aware poll that prints ONE
# stdout line (new mail, timeout guidance, or error) and exits; one watch per
# worktree via an advisory lock in <mail_dir>/.watch/. Kimi sessions wait via
# recurring cron sweeps (see sprint-orchestrator/SKILL.md 'Supervising the Wave').
```

(NOTE: `arm` still ACCEPTS claude until Task 3 — this comment lands with Task 1 because it describes watch; the lint pin flip for arm strings happens in Task 3 with the behavior.)

(c) Add helpers directly after `cursor_file()`:

```bash
watch_lock() {  # advisory one-watch-per-worktree lock, keyed like the cursor
  printf '%s\n' "$mail_dir/.watch/$(printf '%s\n' "$consumer" | cksum | cut -d' ' -f1)"
}
watch_lock_stale() {  # $1=lock — true when past 2x its recorded timeout (prune_stale convention)
  local lt age
  lt="$(sed -n 2p "$1" 2>/dev/null)"; case "$lt" in ''|*[!0-9]*) lt=1800 ;; esac
  age=$(( $(date +%s) - $(stat -f %m "$1" 2>/dev/null || echo 0) ))
  [ "$age" -gt $(( lt * 2 )) ]
}
```

(d) Add the `watch)` case directly after the `wait)` case:

```bash
  watch)
    # Background wait for Claude sessions: the harness launcher turns stdout
    # into the wake event, so every terminal outcome is exactly ONE stdout
    # line — and errors are mirrored to stderr because stderr alone never
    # reaches the event stream (a stderr-only death would be silent).
    pat="${3:-}"; timeout="${4:-1800}"
    [ -n "$pat" ] || usage
    wfail() { printf 'sprint-mail: %s\n' "$1"; printf 'sprint-mail: %s\n' "$1" >&2; exit 2; }
    [ -n "$consumer" ] || wfail "not inside a git worktree — mailbox watches are keyed per worktree; run from the project worktree"
    echo "$timeout" | grep -qE '^[0-9]+$' || wfail "timeout must be whole seconds (got: $timeout)"
    case "$pat" in
      */*|*$'\n'*) wfail "pattern is a mail filename or glob, not a path (got: $pat)" ;;
    esac
    mkdir -p "$mail_dir/.watch"
    lock="$(watch_lock)"
    if [ -f "$lock" ] && watch_lock_stale "$lock"; then rm -f "$lock"; fi
    if ! (set -C; printf '%s\n%s\n' "$$" "$timeout" > "$lock") 2>/dev/null; then
      wfail "a watch is already running for this worktree ($lock) — one watch per worktree; if it died, remove the lock or let stale pruning (age > 2x its timeout) clear it"
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
      printf 'New sprint mail arrived: %s — read it and continue from where you were blocked. Supervisors: sweep ALL new mail with sprint-mail.sh unread, then launch a new watch (sprint-mail.sh supervise) before ending the turn if the wave is still running.\n' "$found"
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

Run: `sprint-orchestrator/test/test-sprint-mail.sh; echo "exit=$?"`
Expected: all cases pass (old and new), `exit=0`.

- [ ] **Step 5: Run the lint**

Run: `test/lint-skills.sh 2>&1 | grep -E '^FAIL|[0-9]+/[0-9]+' | tail -3`
Expected: 0 FAIL — Task 1 adds prose without touching pinned strings (the arm header sentence pinned as "mail: arm requires --harness" etc. is unchanged; verify).

- [ ] **Step 6: Commit**

```bash
git branch --show-current && git status --short
git add sprint-orchestrator/sprint-mail.sh sprint-orchestrator/test/test-sprint-mail.sh
git commit -m "feat(sprint-orchestrator): add sprint-mail watch — cursor-aware background wait"
```

---

### Task 2: Phase 0 transport-selection probe

**Files:**
- Create: `docs/superpowers/plans/2026-07-23-phase0-probe-results.md` (findings record)
- No production code changes.

**Interfaces:**
- Consumes: `sprint-mail.sh watch` from Task 1.
- Produces: `LAUNCHER` decision (`run_in_background` | `monitor`) + the exact instruction sentence Tasks 3-6 render. **Decision rule (from the spec): prefer the candidate that passes idle re-invocation and unattended re-arm; if both pass, prefer `run_in_background`.**

The two candidate instruction sentences (the ONLY strings Task 2's outcome selects between; Tasks 3-6 are written with variant A — if B wins, substitute everywhere Task 3-6 renders it):

- **Variant A (run_in_background, default):** ``launch the watch as a BACKGROUND task (Bash tool, run_in_background: true)``
- **Variant B (Monitor):** ``start a Monitor with this command (persistent: true, description: "sprint mailbox")``

This task runs in a live interactive Claude Code session (the implementing session qualifies). External writers must be `nohup`-detached so they survive the tool call that spawns them. Use a scratch repo so no real mailbox is touched.

- [ ] **Step 1: Fixture**

```bash
P=/private/tmp/claude-501/-Users-rkuprin-claude-skills/512b58b1-5272-4522-8203-4c547172bfe9/scratchpad/probe
mkdir -p "$P/repo" && git -C "$P/repo" init -q
export SM=/Users/rkuprin/claude-skills/sprint-orchestrator/sprint-mail.sh
# All probe commands run: cd "$P/repo" with SPRINT_MAIL_ROOT="$P/mailroot" SPRINT_MAIL_POLL=2
```

- [ ] **Step 2: Candidate A — idle wake.** From `$P/repo`, start a detached writer that posts mail in 60s, launch the watch via Bash `run_in_background: true`, then END THE TURN and let the session sit idle (operator does not type):

```bash
cd "$P/repo" && nohup sh -c 'sleep 60; printf "probe mail\n" | SPRINT_MAIL_ROOT="'"$P"'/mailroot" '"$SM"' post docs/sprints/probe 01 evidence -' >/dev/null 2>&1 &
# then, as its own run_in_background Bash call:
cd "$P/repo" && SPRINT_MAIL_ROOT="$P/mailroot" SPRINT_MAIL_POLL=2 "$SM" watch docs/sprints/probe '01-*-evidence.md' 300
```

Record: did the completion event re-invoke the model with no operator input? How long after the script exited? Did the event text include the one-line wake output?

- [ ] **Step 3: Candidate A — timeout + unattended re-arm.** Launch a watch with timeout 30 and no writer. When its completion wakes the session, immediately re-launch the same watch in that continuation WITHOUT any operator action. Record: did the timeout guidance line arrive? Did the re-launch run without a permission prompt? (Also record which permission rule, if any, `~/.claude/settings.json` needed.)

- [ ] **Step 4: Candidate B — same two experiments via Monitor** (`persistent: true`, description `sprint mailbox probe`). Record the same observations, plus: does a multi-line stdout burst arrive as one event or several (post two mails before a 2s-poll watch with a 2-line test script — verify our one-line protocol is actually load-bearing)?

- [ ] **Step 5: Lifecycle edges (winning candidate only).** Record what happens to the lockfile and the task when: the operator presses Esc mid-turn after launch; the session is closed and resumed (`claude -r`); mail lands while the model is mid-turn (start a watch, keep doing tool work, have the detached writer post during it — when does the event arrive?). Verify a leftover lock is cleared by the stale-prune path (`touch -t 202601010000 <lock>` then relaunch).

- [ ] **Step 6: Longevity soft-check.** Launch a watch with timeout 10800 via the winning candidate and leave it running for the remainder of implementation (≥1h); verify at Task 8 it is still alive or delivered its timeout. Full 3h evidence is allowed to come from the first production wave — record it as a known residual if not proven here.

- [ ] **Step 7: Write `docs/superpowers/plans/2026-07-23-phase0-probe-results.md`** — per candidate, per experiment: observed behavior, timing, the `LAUNCHER` decision with one-sentence rationale, the permission rule needed, and any residuals. If NEITHER candidate passes idle re-invocation: STOP — return to the spec's fallback (shorter budgets) and re-plan; do not proceed to Task 3.

- [ ] **Step 8: Commit**

```bash
git add docs/superpowers/plans/2026-07-23-phase0-probe-results.md
git commit -m "docs(sprint-orchestrator): record Phase 0 watch-transport probe results"
```

---

### Task 3: `supervise --harness claude` prints the watch park; `arm` refuses claude

**Files:**
- Modify: `sprint-orchestrator/sprint-mail.sh` (pre-dispatch harness case ~lines 66-86, `arm)` body ~lines 226-272, `supervise)` ~lines 273-308, usage lines for `arm`)
- Modify: `sprint-orchestrator/test/test-sprint-mail.sh` (claude-arm cases ~lines 128-145)
- Modify: `test/lint-skills.sh` (SMAIL pins ~lines 376-388, REFERENCE pin line 124 — see Step 5)

**Interfaces:**
- Consumes: `watch_lock()`, `watch_lock_stale()` from Task 1; Task 2's `LAUNCHER` sentence.
- Produces: `sprint-mail.sh supervise --harness claude <sprint-dir>` prints the park instruction (or `already watching: <lock>`); `arm --harness claude` exits 2 with a redirect naming the background watch. Tasks 4-6 quote these behaviors in prose.

- [ ] **Step 1: Update the tests.** Two edits in `test-sprint-mail.sh` — placement matters because `$SPRINT_W`/`$WDIR`/`$WLOCK` are defined only in Task 1's appended block near the end of the file.

(1) Replace the claude-arm block IN PLACE (the fixture that fakes `CLAUDE_CONFIG_DIR` with a wired settings.json and asserts `arm --harness claude proceeds`, ~lines 128-145; also drop the dependent case "arm --harness codex still refuses when only Claude is wired") with:

```bash
# ---- arm refuses claude: the Claude wait is a background watch ----
out="$("$SUT" arm --harness claude "$SPRINT" "07-011-reply.md" 900 2>&1)"; rc=$?
[ "$rc" != 0 ] && echo "$out" | grep -q "background watch" \
  && ok "arm --harness claude refused, redirects to watch" \
  || no "arm --harness claude refused, redirects to watch (rc=$rc out=$out)"
```

(2) Append AFTER Task 1's watch block (still before the summary block), where `$SPRINT_W`/`$WDIR`/`$WLOCK` are in scope:

```bash
# ---- supervise --harness claude: prints the watch park, idempotent via lock ----
out="$("$SUT" supervise --harness claude "$SPRINT_W")"; rc=$?
[ "$rc" = 0 ] && echo "$out" | grep -q "watch" && echo "$out" | grep -q "10800" \
  && ok "supervise claude prints the watch park with the idle budget" \
  || no "supervise claude prints the watch park (rc=$rc out=$out)"
echo "$out" | grep -q "run_in_background" \
  && ok "supervise claude names the launcher" || no "supervise claude names the launcher (got: $out)"
echo "$out" | grep -q "END YOUR TURN" \
  && ok "supervise claude ends the turn" || no "supervise claude ends the turn"
mkdir -p "$WDIR/.watch"
printf '99999\n10800\n' > "$WLOCK"
out="$("$SUT" supervise --harness claude "$SPRINT_W")"; rc=$?
[ "$rc" = 0 ] && echo "$out" | grep -q "already watching" \
  && ok "supervise claude is idempotent under a fresh lock" \
  || no "supervise claude is idempotent under a fresh lock (rc=$rc out=$out)"
rm -f "$WLOCK"
```

Keep every other codex arm test untouched — the plain "refused without a wired hook" codex case already covers refusal without the deleted Claude-settings fixture.

- [ ] **Step 2: Run to verify the new cases fail**

Run: `sprint-orchestrator/test/test-sprint-mail.sh 2>&1 | grep '^FAIL'`
Expected: the new claude refusal + supervise cases FAIL; everything else passes.

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

(b) `arm)` body: line 229 message drops `<codex|claude>` → `'arm requires --harness <codex> immediately after…'`; the hook-reference `case "$harness"` (~lines 237-246) loses its `claude)` branch — only the codex `hooks.json` check remains (keep it as a plain statement, no case needed).

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
Claude supervisor park for $sprint_dir — the wait is a background watch: the turn ends, the operator keeps the prompt, the watch's completion event wakes you. Do this now:

1. Launch the watch as a BACKGROUND task (Bash tool, run_in_background: true):
   '$0' watch '$sprint_dir' '$globs' 10800
2. END YOUR TURN. The wake event carries either the new-mail line or the timeout guidance. On every wake: sweep first (sprint-mail.sh unread, then seen), then run 'sprint-mail.sh supervise --harness claude' again if the wave is still running.
3. One watch per worktree — if this printed 'already watching', do not launch another.
EOF
        ;;
```

(If Task 2 selected Monitor, line 1 of the heredoc instruction becomes: `1. Start a Monitor with this command (persistent: true, description: "sprint mailbox"):` — same command line under it.)

(d) usage/header: `arm --harness <codex|claude>` → `arm --harness <codex>` in the top comment (line 7) and `usage()` (line 50).

- [ ] **Step 4: Run the suite**

Run: `sprint-orchestrator/test/test-sprint-mail.sh; echo "exit=$?"`
Expected: all pass, `exit=0`.

- [ ] **Step 5: Update lint pins in the same commit.** In `test/lint-skills.sh`:

- `has "mail: arm usage line" "arm --harness <codex|claude> <sprint-dir> <name-or-glob(s)>"` → `"arm --harness <codex> <sprint-dir> <name-or-glob(s)>"`.
- Replace `has "mail: arm claude branch names installer" "install-claude-hook.sh" "$SMAIL"` with `has "mail: arm refuses claude with redirect" "background watch, not a Stop hook" "$SMAIL"`.
- Add after it:
  ```bash
  has   "mail: watch usage line"                  "watch <sprint-dir> <name-or-glob(s)>" "$SMAIL"
  has   "mail: watch one-line protocol"           "exactly ONE stdout" "$SMAIL"
  has   "mail: claude park prints run-in-background" "run_in_background" "$SMAIL"
  ```
  (If Task 2 selected Monitor, the third pin greps `"persistent: true"` instead.)
- LEAVE lint line 124 (`reference: claude re-arm at idle budget` → REFERENCE.md) untouched — REFERENCE.md still carries the old prose until Task 6; the pin still passes.

Run: `test/lint-skills.sh 2>&1 | tail -3` — Expected: 0 FAIL.

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
- Modify: `sprint-orchestrator/test/test-wave-handoffs.sh` (claude assertion ~line 84)
- Modify: `test/lint-skills.sh` (renderer pin ~line 345)

**Interfaces:**
- Consumes: Task 2's `LAUNCHER` sentence; `watch` CLI shape from Task 1.
- Produces: claude-target kickoffs carry the watch-based `Mailbox wait:` line quoted below; Task 5 mirrors the same form in agent-handoff.

- [ ] **Step 1: Update the test.** In `test-wave-handoffs.sh` replace the line-84 assertion:

```bash
has "claude story renders watch wait line"  "$OUTPUT" "\`~/.claude/skills/sprint-orchestrator/sprint-mail.sh watch '$SPRINT' '08-{SSS}-reply.md' 1800\`"
has "claude watch line backgrounds and ends the turn" "$OUTPUT" "run_in_background: true"
```

(Note the single quotes around `'$SPRINT'` INSIDE the double-quoted needle — the rendered command shell-quotes the sprint dir and the glob, per the spec.)

(Keep the codex assertions at lines 82-83 byte-identical.)

- [ ] **Step 2: Run to verify it fails**

Run: `sprint-orchestrator/test/test-wave-handoffs.sh 2>&1 | grep '^FAIL'`
Expected: the two new claude assertions FAIL.

- [ ] **Step 3: Implement.** In `wave-handoffs.sh`, replace the `*)` (claude) `mailwait` assignment (~line 233) with:

```bash
    *)     contract="~/.claude/skills/agent-handoff/EXECUTION.md"
           mailwait='post your question, then launch the mailbox watch as a BACKGROUND task (Bash tool, run_in_background: true) — `~/.claude/skills/sprint-orchestrator/sprint-mail.sh watch '"'"''"$sprint_dir"''"'"' '"'"''"$story"'-{SSS}-reply.md'"'"' 1800` (SSS = your question'"'"'s sequence) — and END YOUR TURN: the watch'"'"'s completion event wakes you with the reply or the timeout guidance; the operator keeps the prompt. On any wake, or on finding you have no live watch, sweep unread reply mail first (sprint-mail.sh unread), then re-launch only if still waiting. Never foreground the wait.' ;;
```

(The quoting renders `watch '<sprint-dir>' '<NN>-{SSS}-reply.md' 1800` — both arguments single-quoted in the kickoff, matching the Step 1 test needle. Verify by running the renderer once and eyeballing the line before committing.)

(If Task 2 selected Monitor, swap the parenthetical for Variant B's sentence; the command stays identical.)

- [ ] **Step 4: Run the suite**

Run: `sprint-orchestrator/test/test-wave-handoffs.sh; echo "exit=$?"`
Expected: all pass, `exit=0`.

- [ ] **Step 5: Update the lint pin.** Replace `has "renderer: claude arm carries --harness" "arm --harness claude" "$WHS"` with `has "renderer: claude wait is the background watch" "sprint-mail.sh watch" "$WHS"`. Run `test/lint-skills.sh 2>&1 | tail -3` — 0 FAIL.

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
- Modify: `test/lint-skills.sh` (pins ~lines 239, 289)

**Interfaces:**
- Consumes: the exact `Mailbox wait:` claude string from Task 4 (contract and renderer must agree).
- Produces: executor-facing prose for Claude waits; no code.

- [ ] **Step 1: `EXECUTION.md`.** Replace the claude bullet (lines 141-143) with:

```markdown
  - Claude, MAIN session only: launch the mailbox watch as a BACKGROUND task (Bash tool,
    run_in_background: true) — `sprint-mail.sh watch <sprint-dir> {NN}-{SSS}-reply.md 1800` —
    then END YOUR TURN with a one-line status. The watch's completion event wakes you with
    the reply or the timeout guidance; the operator keeps the prompt. On any wake, or on
    finding you have no live watch, sweep unread reply mail first (`sprint-mail.sh unread`),
    then re-launch only if still waiting. Never foreground the watch, and never `arm` —
    Claude has no Stop-hook wait.
```

- [ ] **Step 2: `SKILL.md`.** At ~line 172-173, replace `Claude targets (claude-cli, claude-session) render the claude arm-and-end-turn form (`arm --harness claude …`)` with `Claude targets (claude-cli, claude-session) render the claude background-watch form (`sprint-mail.sh watch …`, launched run_in_background)`. In the line-199 template, replace the claude segment (between the first and second `|`) with the exact `mailwait` string Task 4 renders (substituting `{SPRINT_DIR}`/`{NN}` for the runtime values, matching the codex segment's placeholder style):

```
post your question, then launch the mailbox watch as a BACKGROUND task (Bash tool, run_in_background: true) — `~/.claude/skills/sprint-orchestrator/sprint-mail.sh watch '{SPRINT_DIR}' '{NN}-{SSS}-reply.md' 1800` (SSS = your question's sequence) — and END YOUR TURN: the watch's completion event wakes you with the reply or the timeout guidance; the operator keeps the prompt. On any wake, or on finding you have no live watch, sweep unread reply mail first (sprint-mail.sh unread), then re-launch only if still waiting. Never foreground the wait.
```

- [ ] **Step 3: Update lint pins.** Replace line 239's `has "handoff: claude wait form is arm-and-end-turn" "arm --harness claude {SPRINT_DIR} {NN}-{SSS}-reply.md 1800" "$AH"` with `has "handoff: claude wait form is the background watch" "sprint-mail.sh watch '{SPRINT_DIR}' '{NN}-{SSS}-reply.md' 1800" "$AH"` (needle matches the quoted template exactly). Replace line 289's `has "contract: claude main-session arm wait" …` with `has "contract: claude main-session watch wait" "sprint-mail.sh watch <sprint-dir> {NN}-{SSS}-reply.md 1800" "$AHEXEC"`.

- [ ] **Step 4: Run lint + handoff-adjacent suites**

Run: `test/lint-skills.sh 2>&1 | tail -3 && sprint-orchestrator/test/test-wave-handoffs.sh >/dev/null; echo "exit=$?"`
Expected: 0 FAIL, exit=0.

- [ ] **Step 5: Commit**

```bash
git add agent-handoff/EXECUTION.md agent-handoff/SKILL.md test/lint-skills.sh
git commit -m "docs(agent-handoff): claude wait form is the background watch"
```

---

### Task 6: sprint-orchestrator prose — REFERENCE.md + README.md

**Files:**
- Modify: `sprint-orchestrator/REFERENCE.md` (Claude bullet lines 145-149; subagent sentence lines 187-194)
- Modify: `sprint-orchestrator/README.md` ("Reactive waits on Claude" section lines 222-250; "The mailbox" mentions ~line 227-228; subagent sentence ~line 169)
- Modify: `test/lint-skills.sh` (pins: line 124; sprint-readme block ~lines 397-408)
- Check-only: `sprint-orchestrator/SKILL.md` (grep, expect no hits)

**Interfaces:**
- Consumes: park instruction wording from Task 3; watch CLI from Task 1.
- Produces: operator/supervisor-facing prose; the "Mailbox mechanics" Claude bullet Tasks 7-8 verify against.

- [ ] **Step 1: REFERENCE.md Claude bullet** (lines 145-149) becomes:

```markdown
- **Claude**: supervise prints the watch park — launch
  `sprint-mail.sh watch <sprint-dir> '*-question.md *-concluded.md' 10800` as a background
  task (Bash `run_in_background: true`) and end the turn; the watch's completion event
  wakes the session, and the operator keeps the prompt throughout. Nothing to install.
  One watch per worktree (advisory lock; `supervise` prints `already watching` instead of
  a duplicate park). The session's permission posture must let the watch command launch
  unattended — after a wake, the re-park happens with no operator present; a permission
  prompt there kills reactive supervision. Main sessions only.
```

- [ ] **Step 2: REFERENCE.md subagent sentence** (~line 189): replace `a subagent never arms a blocking mailbox wait — the Stop hook never fires for it, on any harness — so its` with `a subagent never parks on a mailbox wait — no wake can reach it after it returns, on any harness — so its`.

- [ ] **Step 3: README.md "Reactive waits on Claude"** (lines 222-250) — replace the whole section with:

```markdown
### Reactive waits on Claude — nothing to install (main sessions)

A main-session Claude supervisor or executor waits by launching the mailbox watch as a
background task and ending its turn: `sprint-mail.sh watch <sprint-dir>
<reply-file-or-globs> [<timeout>]` under Bash `run_in_background: true` (supervise prints
the exact park). The watch polls the mailbox against the worktree's read-cursor and exits
with ONE line — the new-mail wake or the timeout guidance — and that completion event
wakes the session. The operator keeps the prompt the whole time; there is no Stop hook,
no arm record, and nothing to install. One watch per worktree, enforced by an advisory
lock under the mailbox's `.watch/` dir (stale locks age out at 2x their timeout).
Budgets: 10800 for the supervisor idle sweep, 1800 for targeted reply waits. The session's
permission posture must allow the watch command to launch unattended — re-parking after a
wake happens with no operator present. Main sessions only: an in-session subagent cannot
be woken after it returns, so rendered subagent kickoffs carry the non-arming fallback.

Machines that ran the retired `install-claude-hook.sh`: delete the `claude-stop-wait.sh`
Stop group from `~/.claude/settings.json` (leave co-installed Stop hooks untouched) —
the hook and installer no longer exist in this repo, and a settings entry pointing at a
deleted file errors on every Stop.
```

Also update ~line 169 (`subagents — those carry the non-arming \`Mailbox wait:\``): replace its Stop-hook rationale with the "no wake can reach a returned subagent" wording, and the intro mention at ~line 227 if it names `install-claude-hook.sh`.

- [ ] **Step 4: Update lint pins.**

- Line 124: `has "reference: claude re-arm at idle budget" "arm --harness claude …10800" "$ORCH_REF"` → `has "reference: claude watch at idle budget" "watch <sprint-dir> '*-question.md *-concluded.md' 10800" "$ORCH_REF"`.
- Sprint-readme block: drop `has "sprint readme: names the claude installer" …`, `has "sprint readme: claude arm carries --harness" …`, `has "sprint readme: claude budget note" "timeout: 10860" …`; keep the codex pins; the parallel-hook pin (`holds the Stop event's completion`) stays only if that sentence survives in the Codex section — check; if it was in the Claude section, move the pin to grep the Codex section's equivalent or drop it with a comment.
- Add: `has "sprint readme: claude waits need no install" "Reactive waits on Claude — nothing to install" "$ORCH_README"` and `has "sprint readme: claude migration note" "delete the \`claude-stop-wait.sh\` Stop group" "$ORCH_README"` and `has "reference: claude unattended permission note" "launch unattended" "$ORCH_REF"`.

- [ ] **Step 5: SKILL.md check.** Run: `grep -n "arm --harness claude\|claude-stop-wait\|install-claude-hook\|Stop hook" sprint-orchestrator/SKILL.md` — expected: no hits (the constitution speaks of waits abstractly). If a hit appears, update only that sentence to the watch wording.

- [ ] **Step 6: Run lint**

Run: `test/lint-skills.sh 2>&1 | tail -3`
Expected: 0 FAIL.

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
- Modify: `sprint-orchestrator/codex-stop-wait.sh` (header only), `README.md` (root, ~lines 48-52 and 77-80), `INSTALL.md` (Claude hook step ~lines 48-59; verify list ~lines 71-80), `test/lint-skills.sh` (claude hook/installer pins ~lines 365-375, 392-396, 410, 419-421)

**Interfaces:**
- Consumes: Task 6's completed prose (repo docs no longer point at the installer).
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

Expected: `removed 1 Stop group; N kept`, then `clean`, and the co-installed (iTerm-status) Stop hook still listed.

- [ ] **Step 2: Drain stale claude wait records.**

```bash
ls -la "$HOME/.sprint-mail/.codex-waits/" 2>/dev/null || echo "no waits dir"
```

For each record present: read line 1 (worktree). If it belongs to a worktree with a live **Codex** wait, leave it. Otherwise run `sprint-mail.sh disarm <sprint-dir>` from that worktree (or `sprint-mail.sh disarm <sprint-dir> --stale` for age-based pruning). Never `rm` the directory wholesale.

- [ ] **Step 3: Delete the files.**

```bash
git rm sprint-orchestrator/claude-stop-wait.sh sprint-orchestrator/install-claude-hook.sh \
       sprint-orchestrator/test/test-claude-stop-wait.sh sprint-orchestrator/test/test-install-claude-hook.sh
```

- [ ] **Step 4: `codex-stop-wait.sh` header.** Remove the sentence claiming the body is kept byte-identical to the (now deleted) Claude hook — in its header comment, replace the paragraph mentioning `claude-stop-wait.sh` / "BYTE-IDENTICAL" with: `# The Codex Stop hook is the only Stop-hook wait — Claude parks via 'sprint-mail.sh watch' as a background task; Kimi via cron sweeps.` Keep the body untouched.

- [ ] **Step 5: Root README + INSTALL.**

- Root `README.md` ~line 49: `(including the sprint mailbox Stop hook on Codex machines)` stays true — verify wording still says Codex only; ~lines 77-80: drop `install-claude-hook.sh` / "Reactive waits on Claude" from the hook sentence, e.g.: ``machine-specific setup: `sprint-orchestrator/install-codex-hook.sh` (Codex) — details in [`sprint-orchestrator/README.md`], "Reactive waits on Codex". Claude and Kimi need no hook — Claude waits are background watch tasks, Kimi waits are cron sweeps ("Reactive waits on Claude" / "on Kimi").``
- `INSTALL.md`: replace the "Claude Code present:" install block (~lines 48-59) with: `- Claude Code present: nothing to wire — Claude waits are background watch tasks the session launches itself. Details: [sprint-orchestrator/README.md], "Reactive waits on Claude". If ~/.claude/settings.json still carries a claude-stop-wait.sh Stop group from an earlier install, delete that group (leave other Stop hooks).` Remove `test-claude-stop-wait.sh` and `test-install-claude-hook.sh` from the verify list.

- [ ] **Step 6: Lint pins.** In `test/lint-skills.sh`:

- Delete the CLSW block (lines 365-369), the byte-identical diff pin (lines 370-376), the CLINSTALLER block (lines 392-396).
- Replace `has "repo readme: names the claude hook setup" "install-claude-hook.sh" …` with `has "repo readme: claude needs no hook" "Claude and Kimi need no hook" "$HERE/../README.md"`.
- Replace INSTALL pins 419-421 (`wires the claude hook`, `runs the claude hook suite`, `runs the claude installer suite`) with `has "install guide: claude needs no wiring" "nothing to wire — Claude waits are background watch tasks" "$INSTALL"` and `hasnt "install guide: no claude hook installer" "./sprint-orchestrator/install-claude-hook.sh" "$INSTALL"`.
- Add to the CSW block: `hasnt "stop-wait: codex hook is the only stop hook" "claude-stop-wait" "$CSW"` — guards against the deleted name creeping back.

- [ ] **Step 7: Run everything that still exists**

Run: `test/lint-skills.sh 2>&1 | tail -3 && sprint-orchestrator/test/test-sprint-mail.sh >/dev/null && sprint-orchestrator/test/test-codex-stop-wait.sh >/dev/null && sprint-orchestrator/test/test-install-codex-hook.sh >/dev/null && sprint-orchestrator/test/test-wave-handoffs.sh >/dev/null && sprint-orchestrator/test/test-sprint-status.sh >/dev/null; echo "exit=$?"`
Expected: 0 FAIL, exit=0.

- [ ] **Step 8: Commit**

```bash
git branch --show-current && git status --short
git add -u sprint-orchestrator/ README.md INSTALL.md test/lint-skills.sh
git status --short   # verify ONLY the intended paths are staged
git commit -m "chore(sprint-orchestrator): retire the claude Stop hook — watch is the wait"
```

---

### Task 8: End-to-end smoke + longevity check

**Files:** none new (verification only; probe-results doc may gain a longevity line).

- [ ] **Step 1: Full suite sweep**

Run: `test/lint-skills.sh 2>&1 | tail -1 && for t in sprint-orchestrator/test/test-*.sh codex/test/test.sh; do "$t" >/dev/null 2>&1 && echo "ok $t" || echo "FAIL $t"; done`
Expected: no FAIL lines; lint tally shows 0 failures.

- [ ] **Step 2: Live park smoke.** In the implementing session, from a scratch repo fixture (Task 2's), run `sprint-mail.sh supervise --harness claude <fixture-sprint>` and follow its printed instruction literally: launch the watch, end the turn, have a detached writer post a question 60s later. Verify: session woke with the one-line event, swept with `unread`/`seen`, re-parked via `supervise` (which printed the park again, not `already watching`, since the first watch exited), all with zero operator input and zero permission prompts.

- [ ] **Step 3: Longevity result.** Check Task 2 Step 6's long watch: still alive or cleanly delivered. Append the observation to `docs/superpowers/plans/2026-07-23-phase0-probe-results.md`; if the 3h budget remains unproven, record it as a residual to confirm on the first production wave.

- [ ] **Step 4: Commit (only if the probe doc changed)**

```bash
git add docs/superpowers/plans/2026-07-23-phase0-probe-results.md
git commit -m "docs(sprint-orchestrator): record watch longevity observation"
```
