# Mailbox wake — Phase 1: record semantics (worktree identity, cursor-path record, dual-reader, reaper)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the mailbox wait record identity-stable and cursor-based, with a dual-reader that keeps the Codex Stop hook green on both legacy and new records, and a reaper that drains orphaned records — the shared foundation the Claude hook (Phase 2) builds on.

**Architecture:** The read-cursor is re-keyed from raw `pwd` to the git worktree root. `arm` writes a 4-line record `{worktree-root, glob(s), timeout, cursor-path}` (no `since`). Both hooks become dual-readers: an absolute-path line 4 is a new (cursor) record matched by worktree root; an all-digits line 4 is a legacy (epoch) record matched by physical cwd. A stale/orphan reaper prunes records whose identity directory is gone or which are long past budget.

**Tech Stack:** Bash 3.2, coreutils only (`git rev-parse`, `cksum`, `stat`, `sed`, `grep`, `ls`). Tests and lint are bash + `grep`.

This is Phase 1 of the spec `docs/superpowers/specs/2026-07-19-unified-mailbox-wake-design.md`. Phase 2 (Claude hook, installer, `--harness`, live interruptibility gate) and Phase 3 (prose, topology-aware rendering, READMEs) are separate plans written after this lands.

## Global Constraints

- **Bash 3.2, coreutils only.** No `jq`, no GNU-only flags.
- **Both hooks stay green on legacy AND new records at every commit** (dual-reader). A legacy record (numeric line 4, cwd identity) must behave exactly as today.
- **The cursor and wait record are never sprint state.** `sprint-status.sh` never reads them; deleting one loses nothing. Re-keying the cursor is safe (worst case: a consumer re-reads already-seen mail once).
- **Pruning an orphan is always safe** — it helps no one; the reaper only removes records whose identity directory is gone or which are >2× their timeout old.
- **Prose is pinned by lint; update `test/lint-skills.sh` in the same commit as pinned changes.**
- **Surgical scope.** Touch only `sprint-orchestrator/sprint-mail.sh`, `sprint-orchestrator/codex-stop-wait.sh`, their two test files, and `test/lint-skills.sh`. Do NOT add `--harness`, the Claude hook, or any prose (those are Phases 2–3).
- **Every commit** ends with the standard `Co-Authored-By:` and `Claude-Session:` trailers.
- **One mailbox consumer per worktree** is the new invariant; `unread`/`seen`/`arm`/`disarm` require a git worktree and fail loudly otherwise.

---

### Task 1: Re-key the read-cursor to the git worktree root

**Files:**
- Modify: `sprint-orchestrator/sprint-mail.sh` (add `consumer` after `mail_dir` ~line 61; rewrite `cursor_file` ~lines 70–76; add a worktree guard to the `unread`/`seen` arms)
- Test: `sprint-orchestrator/test/test-sprint-mail.sh` (invert the per-cwd cursor case)

**Interfaces:**
- Produces: a top-level `consumer` = canonical git worktree root (or empty outside a worktree); `cursor_file` keyed by `cksum` of `consumer`.

- [ ] **Step 1: Rewrite the per-cwd cursor test to expect per-worktree sharing**

In `sprint-orchestrator/test/test-sprint-mail.sh`, replace the block:

```bash
# cursor is per-cwd: same mailbox, a different cwd still sees q2 unread
"$SUT" seen "$SPRINT2" "$q2"
mkdir -p "$REPO_A/deep/sub"; cd "$REPO_A/deep/sub"
u_sub="$("$SUT" unread "$SPRINT2" '05-004-question.md')"
[ "$u_sub" = "$q2" ] && ok "cursor is per-cwd (other cwd still sees q2 unread)" || no "cursor is per-cwd (got: $u_sub)"
cd "$REPO_A"
```

with:

```bash
# cursor is per-worktree: a subdirectory of the same worktree SHARES the cursor
"$SUT" seen "$SPRINT2" "$q2"
mkdir -p "$REPO_A/deep/sub"; cd "$REPO_A/deep/sub"
u_sub="$("$SUT" unread "$SPRINT2" '05-004-question.md')"
[ -z "$u_sub" ] && ok "cursor is per-worktree (subdir shares the cursor)" || no "cursor is per-worktree (got: $u_sub)"
cd "$REPO_A"
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `sprint-orchestrator/test/test-sprint-mail.sh`
Expected: FAIL on `cursor is per-worktree (subdir shares the cursor)` — the current `pwd`-keyed cursor gives the subdir a *different* key, so `q2` still shows unread there.

- [ ] **Step 3: Add the `consumer` identity and re-key `cursor_file`**

In `sprint-orchestrator/sprint-mail.sh`, after `mail_dir="$MAIL_ROOT/$repo/$(basename "$sprint_dir")"` (~line 61) add:

```bash
# Stable per-worktree consumer identity (empty outside a worktree). The cursor
# and wait records key on this so a consumer that cd's into a subdirectory does
# not fragment its cursor. One mailbox consumer per worktree.
consumer="$(git rev-parse --show-toplevel 2>/dev/null)" \
  && consumer="$(cd "$consumer" && pwd -P)" || consumer=""
```

Replace `cursor_file` (~lines 70–76) with:

```bash
cursor_file() {  # per-consumer read-cursor path, keyed by the worktree root
  printf '%s\n' "$mail_dir/.read/$(printf '%s\n' "$consumer" | cksum | cut -d' ' -f1)"
}
```

At the top of the `unread)` arm (right after `pat="${3:-}"` / `[ -n "$pat" ] || usage`) and the top of the `seen)` arm (right after `shift 2` / the arg check), add the guard:

```bash
    [ -n "$consumer" ] || err "not inside a git worktree — mailbox cursors are keyed per worktree; run from the project worktree"
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `sprint-orchestrator/test/test-sprint-mail.sh`
Expected: PASS — `N passed, 0 failed`. The subdir now resolves to the same worktree root, so `q2` is already `seen` and `unread` returns nothing.

- [ ] **Step 5: Commit**

```bash
git add sprint-orchestrator/sprint-mail.sh sprint-orchestrator/test/test-sprint-mail.sh
git commit -m "feat(sprint): key the mailbox cursor by worktree root"
# (append the standard Co-Authored-By / Claude-Session trailers)
```

---

### Task 2: Dual-reader Codex Stop hook (cursor for new records, epoch for legacy)

**Files:**
- Modify: `sprint-orchestrator/codex-stop-wait.sh` (full rewrite of the record-scan + poll)
- Test: `sprint-orchestrator/test/test-codex-stop-wait.sh` (git-init the cwd; since-epoch cases → cursor cases; add a legacy case; `arm()` helpers write 4 lines)

**Interfaces:**
- Consumes: 4-line records — new `{worktree-root, glob(s), timeout, /abs/cursor}` or legacy `{cwd, glob(s), timeout, epoch}`.
- Produces: the hook wakes (`exit 2`) on an unread-against-cursor match (new) or an `mtime >= since` match (legacy); silent `exit 0` when no record matches this session.

- [ ] **Step 1: Rewrite the hook test to drive both record formats**

In `sprint-orchestrator/test/test-codex-stop-wait.sh`:

(a) after `mkdir -p "$WAITS" "$MDIR" "$TMP/cwd"`, make the cwd a worktree so worktree-root identity resolves:

```bash
git -C "$TMP/cwd" init -q
```

(b) replace the single `arm()` helper with two — legacy (epoch) and new (cursor):

```bash
WTROOT="$(cd "$TMP/cwd" && pwd -P)"
arm() {  # legacy record: $1=glob(s) $2=timeout $3=since-epoch  (identity = cwd)
  printf '%s\n%s\n%s\n%s\n' "$(pwd -P)" "$1" "$2" "$3" > "$WAITS/.tmp.$$" \
    && mv "$WAITS/.tmp.$$" "$WAITS/wait-t"
}
arm_cursor() {  # new record: $1=glob(s) $2=timeout $3=/abs/cursor  (identity = worktree root)
  printf '%s\n%s\n%s\n%s\n' "$WTROOT" "$1" "$2" "$3" > "$WAITS/.tmp.$$" \
    && mv "$WAITS/.tmp.$$" "$WAITS/wait-t"
}
```

(c) replace the two `since-epoch` cases (the block from `# ---- since-epoch: mail older than the arm never wakes the turn ----` through the "new mail on a glob wakes the turn" assertion) with cursor-record cases plus one retained legacy case:

```bash
# ---- new record: a file already in the cursor does NOT wake (times out) ----
mkdir -p "$MDIR/.read"
echo "03-001-question.md" > "$MDIR/.read/cur"          # already seen
echo body > "$MDIR/03-001-question.md"
arm_cursor "$MDIR/03-*-question.md" 2 "$MDIR/.read/cur"
out="$(: | "$SUT" 2>&1)"
case "$out" in *"timed out"*) ok "cursor: seen file does not wake" ;; *) no "cursor: seen file does not wake (got: $out)" ;; esac

# ---- new record: an unread file matching the glob DOES wake ----
arm_cursor "$MDIR/03-*-question.md" 30 "$MDIR/.read/cur"
( sleep 2; echo body > "$MDIR/03-002-question.md" ) &   # not in cursor
out="$(: | "$SUT" 2>&1)"; rc=$?
wait
[ "$rc" = "2" ] && case "$out" in *"03-002-question.md"*) ok "cursor: unread file wakes the turn" ;; *) no "cursor: unread file wakes the turn (got: $out)" ;; esac || no "cursor: unread file wakes (rc=$rc)"

# ---- legacy record still honored: mail older than the epoch does not wake ----
echo old > "$MDIR/02-001-question.md"
arm "$MDIR/02-*-question.md" 2 "$(( $(stat -f %m "$MDIR/02-001-question.md") + 1 ))"
out="$(: | "$SUT" 2>&1)"
case "$out" in *"timed out"*) ok "legacy: pre-arm mail filtered by since-epoch" ;; *) no "legacy: pre-arm mail filtered by since-epoch (got: $out)" ;; esac
```

- [ ] **Step 2: Run the hook test to verify it fails**

Run: `sprint-orchestrator/test/test-codex-stop-wait.sh`
Expected: FAIL — the current hook reads line 4 only as a numeric epoch and matches identity only against `pwd`, so the two `arm_cursor` (path line 4) cases do not behave correctly.

- [ ] **Step 3: Rewrite `codex-stop-wait.sh` as a dual-reader**

Replace the entire contents of `sprint-orchestrator/codex-stop-wait.sh` with:

```bash
#!/usr/bin/env bash
# codex-stop-wait.sh — Codex Stop hook: hold the turn open while an armed
# sprint-mail wait is pending for this session.
#
# Records live under ${SPRINT_MAIL_ROOT:-~/.sprint-mail}/.codex-waits/, four
# lines. Two formats coexist during the cursor migration (dual-reader):
#   NEW    — worktree root, absolute glob(s), timeout, ABSOLUTE cursor path.
#            A file wakes the turn iff its basename is NOT a line in the cursor.
#   LEGACY — physical cwd, absolute glob(s), timeout, NUMERIC since-epoch.
#            A file wakes the turn iff its mtime >= since. Kept until in-flight
#            legacy records drain, then removable.
# Line 4 discriminates: an absolute path (/...) is NEW; all-digits is LEGACY.
# Identity matches line 1 against the worktree root (NEW) or the cwd (LEGACY).
#
# Exit 0  — no armed wait for this session: let the turn end normally.
# Exit 2  — stderr becomes a synthetic continuation prompt.
set -u

cat > /dev/null   # drain the Stop payload

WAITS_DIR="${SPRINT_MAIL_ROOT:-$HOME/.sprint-mail}/.codex-waits"
[ -d "$WAITS_DIR" ] || exit 0

cwd="$(pwd -P)"
wtroot="$(git rev-parse --show-toplevel 2>/dev/null)" && wtroot="$(cd "$wtroot" && pwd -P)" || wtroot=""

rec=""
for f in "$WAITS_DIR"/*; do
  [ -f "$f" ] || continue
  l1="$(sed -n 1p "$f")"; l4="$(sed -n 4p "$f")"
  mine=0
  case "$l4" in
    /*)          [ -n "$wtroot" ] && [ "$l1" = "$wtroot" ] && mine=1 ;;   # NEW (cursor)
    ''|*[!0-9]*) : ;;                                                     # malformed
    *)           [ "$l1" = "$cwd" ] && mine=1 ;;                          # LEGACY (epoch)
  esac
  [ "$mine" = 1 ] || continue
  if [ -n "$rec" ]; then
    echo "codex-stop-wait: two armed waits for this session — run sprint-mail.sh disarm, then re-arm once." >&2
    exit 2
  fi
  rec="$f"
done
[ -n "$rec" ] || exit 0

glob="$(sed -n 2p "$rec")"
timeout="$(sed -n 3p "$rec")"
l4="$(sed -n 4p "$rec")"
case "$timeout" in *[!0-9]*|'') timeout=1800 ;; esac
case "$l4" in
  /*) mode=cursor; cursor="$l4"; since=0 ;;
  *)  mode=epoch;  cursor="";    since="$l4"; case "$since" in *[!0-9]*|'') since=0 ;; esac ;;
esac

poll="${SPRINT_MAIL_POLL:-2}"
elapsed=0
found=""
while :; do
  for f in $glob; do
    [ -e "$f" ] || continue
    if [ "$mode" = cursor ]; then
      grep -qxF "$(basename "$f")" "$cursor" 2>/dev/null && continue      # already read
    else
      [ "$(stat -f %m "$f" 2>/dev/null || echo 0)" -ge "$since" ] || continue
    fi
    found="${found}${found:+ }$f"
  done
  [ -n "$found" ] && break
  [ "$elapsed" -ge "$timeout" ] && break
  sleep "$poll"
  elapsed=$((elapsed + poll))
done

rm -f "$rec"
if [ -n "$found" ]; then
  echo "New sprint mail arrived: $found — read it and continue from where you were blocked. Supervisors: sweep ALL new mail with sprint-mail.sh list, then re-arm before ending the turn if the wave is still running." >&2
else
  echo "Armed mailbox wait timed out after ${timeout}s with no new mail. Executors: take the contract's no-reply fallback (handback/blocked) and post your terminal concluded. Supervisors: sweep, then re-arm if the wave is still running." >&2
fi
exit 2
```

- [ ] **Step 4: Run the hook test to verify it passes**

Run: `sprint-orchestrator/test/test-codex-stop-wait.sh`
Expected: PASS — `N passed, 0 failed`. Cursor cases wake on unread / stay quiet on seen; the legacy epoch case still filters pre-arm mail; existing no-record / reply-arrival / timeout / double-arm / foreign-record cases still pass.

- [ ] **Step 5: Commit**

```bash
git add sprint-orchestrator/codex-stop-wait.sh sprint-orchestrator/test/test-codex-stop-wait.sh
git commit -m "feat(sprint): dual-reader Codex stop hook (cursor + legacy epoch)"
# (append the standard Co-Authored-By / Claude-Session trailers)
```

---

### Task 3: `arm` writes the new cursor-path record

**Files:**
- Modify: `sprint-orchestrator/sprint-mail.sh` (`arm)` arm ~lines 127–161; `usage()` and header comment; add the `unread`/`seen`-style guard to `arm)`)
- Test: `sprint-orchestrator/test/test-sprint-mail.sh` (arm record assertions)

**Interfaces:**
- Produces: `arm <sprint-dir> <name-or-glob(s)> [<timeout>]` writes `{worktree-root, abs glob(s), timeout, cursor-path}`; double-arm is keyed by worktree root. The `<since-epoch>` 5th arg is removed.

- [ ] **Step 1: Update the arm record assertions**

In `sprint-orchestrator/test/test-sprint-mail.sh`, in the arm block, replace these assertions:

```bash
[ "$(sed -n 1p "$rec")" = "$(pwd -P)" ] && ok "arm line 1 is canonical cwd" || no "arm line 1 is canonical cwd"
```
→
```bash
[ "$(sed -n 1p "$rec")" = "$(cd "$REPO_A" && pwd -P)" ] && ok "arm line 1 is the worktree root" || no "arm line 1 is the worktree root"
```

```bash
sed -n 4p "$rec" | grep -qE '^[0-9]+$' && ok "arm line 4 defaults to a now epoch" || no "arm line 4 defaults to a now epoch"
```
→
```bash
case "$(sed -n 4p "$rec")" in "$MDIR/.read/"*) ok "arm line 4 is the cursor path" ;; *) no "arm line 4 is the cursor path (got: $(sed -n 4p "$rec"))" ;; esac
```

And replace the multi-glob + since-epoch case:

```bash
"$SUT" arm "$SPRINT" "07-*-reply.md 07-*-note.md" 900 7777 >/dev/null \
  && rec2="$(ls "$WAITS"/wait-* 2>/dev/null | head -1)" \
  && [ "$(sed -n 2p "$rec2")" = "$MDIR/07-*-reply.md $MDIR/07-*-note.md" ] \
  && [ "$(sed -n 4p "$rec2")" = "7777" ] \
  && ok "arm accepts multiple globs unexpanded and an explicit since-epoch" \
  || no "arm accepts multiple globs unexpanded and an explicit since-epoch"
```
→
```bash
"$SUT" arm "$SPRINT" "07-*-reply.md 07-*-note.md" 900 >/dev/null \
  && rec2="$(ls "$WAITS"/wait-* 2>/dev/null | head -1)" \
  && [ "$(sed -n 2p "$rec2")" = "$MDIR/07-*-reply.md $MDIR/07-*-note.md" ] \
  && case "$(sed -n 4p "$rec2")" in "$MDIR/.read/"*) true ;; *) false ;; esac \
  && ok "arm accepts multiple globs unexpanded, line 4 is the cursor path" \
  || no "arm accepts multiple globs unexpanded, line 4 is the cursor path"
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `sprint-orchestrator/test/test-sprint-mail.sh`
Expected: FAIL on the arm line-1 / line-4 assertions — arm still writes `pwd` on line 1 and a numeric epoch on line 4.

- [ ] **Step 3: Rewrite the `arm)` arm**

In `sprint-orchestrator/sprint-mail.sh`, replace the `arm)` case body (from `pat="${3:-}"; timeout="${4:-1800}"; since="${5:-}"` through the closing `;;`) with:

```bash
  arm)
    pat="${3:-}"; timeout="${4:-1800}"
    [ -n "$pat" ] || usage
    [ -n "$consumer" ] || err "not inside a git worktree — mailbox waits are keyed per worktree; run from the project worktree"
    # An armed record only works if the Stop hook is wired — otherwise the turn
    # ends and nothing ever wakes, the exact orphaned-wait failure arm exists to
    # prevent. Refuse loudly instead of arming a dead wait.
    hooks_json="${CODEX_HOME:-$HOME/.codex}/hooks.json"
    grep -q "codex-stop-wait.sh" "$hooks_json" 2>/dev/null \
      || err "codex Stop hook not wired in $hooks_json — run sprint-orchestrator/install-codex-hook.sh once on this machine, or take the contract's no-wait fallback instead of arming"
    echo "$timeout" | grep -qE '^[0-9]+$' || err "timeout must be whole seconds (got: $timeout)"
    case "$pat" in
      */*|*$'\n'*) err "pattern is a mail filename or glob, not a path (got: $pat)" ;;
    esac
    waits_dir="$MAIL_ROOT/.codex-waits"
    mkdir -p "$waits_dir"
    prune_stale "$waits_dir"
    for f in "$waits_dir"/*; do
      [ -f "$f" ] || continue
      [ "$(sed -n 1p "$f")" = "$consumer" ] \
        && err "a wait is already armed for this worktree — run 'sprint-mail.sh disarm' first"
    done
    abs=""
    set -f
    for p in $pat; do abs="$abs${abs:+ }$mail_dir/$p"; done
    set +f
    cur="$(cursor_file)"
    rec="$waits_dir/wait-$$-$(date +%s)"
    tmp="$waits_dir/.tmp.$$"
    printf '%s\n%s\n%s\n%s\n' "$consumer" "$abs" "$timeout" "$cur" > "$tmp" && mv "$tmp" "$rec"
    printf '%s\n' "$rec"
    ;;
```

Update the `usage()` heredoc arm line and header comment — drop `[<since-epoch>]`:

```
       sprint-mail.sh arm <sprint-dir> <name-or-glob(s)> [<timeout-seconds>]
```

(both in the `usage()` block and the top-of-file synopsis comment). Note: `prune_stale` is added in Task 4; this task references it, so Task 4 must land in the same branch — but to keep this commit runnable on its own, define a temporary no-op is NOT needed because Task 4's `prune_stale` is added to the same file before this arm runs in tests only if ordered first. **Order Task 4 before Task 3's commit, or fold `prune_stale`'s definition into this step.** (This plan folds the `prune_stale` definition into Task 4 Step 3 and orders Task 4's function-definition step before running Task 3's tests — see Task 4.)

- [ ] **Step 4: Run the full mail suite to verify it passes** (after Task 4's `prune_stale` is defined)

Run: `sprint-orchestrator/test/test-sprint-mail.sh`
Expected: PASS.

- [ ] **Step 5: Commit** (together with Task 4, since `arm` calls `prune_stale`)

Deferred to Task 4's commit.

---

### Task 4: Stale/orphan reaper (`prune_stale`, `disarm --stale`)

**Files:**
- Modify: `sprint-orchestrator/sprint-mail.sh` (add `prune_stale` helper; `disarm)` gains `--stale`; header/usage)
- Test: `sprint-orchestrator/test/test-sprint-mail.sh` (reaper cases)

**Interfaces:**
- Produces: `prune_stale <waits-dir>` removes records whose line-1 dir is gone or which are >2× their timeout old; `disarm <sprint-dir> --stale` runs it.

- [ ] **Step 1: Add the reaper tests**

In `sprint-orchestrator/test/test-sprint-mail.sh`, after the existing arm/disarm block, add:

```bash
# ---- reaper: arm prunes a dead-identity record before its double-arm check ----
DEAD="$WAITS/wait-dead"
printf '/no/such/dir/gone\n%s\n900\n%s\n' "$MDIR/07-*-reply.md" "$MDIR/.read/x" > "$DEAD"
"$SUT" arm "$SPRINT" "07-050-reply.md" 900 >/dev/null
[ ! -f "$DEAD" ] && ok "arm prunes a record whose identity dir is gone" || no "arm prunes a dead-identity record"
"$SUT" disarm "$SPRINT"

# ---- reaper: disarm --stale sweeps an expired record ----
OLD="$WAITS/wait-old"
printf '%s\n%s\n1\n%s\n' "$(cd "$REPO_A" && pwd -P)" "$MDIR/07-*-reply.md" "$MDIR/.read/x" > "$OLD"
# backdate it well past 2x its 1s timeout
touch -t 202607140000 "$OLD"
"$SUT" disarm "$SPRINT" --stale
[ ! -f "$OLD" ] && ok "disarm --stale sweeps an expired record" || no "disarm --stale sweeps an expired record"
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `sprint-orchestrator/test/test-sprint-mail.sh`
Expected: FAIL — `prune_stale` does not exist and `disarm --stale` is unhandled (the dead/old records survive).

- [ ] **Step 3: Add `prune_stale` and rewrite `disarm)`**

In `sprint-orchestrator/sprint-mail.sh`, add the helper next to `cursor_file` (before `case "$cmd" in`):

```bash
prune_stale() {  # $1=waits_dir — drop records whose identity dir is gone or which are long expired
  local wd="$1" f id ts age now
  now="$(date +%s)"
  for f in "$wd"/*; do
    [ -f "$f" ] || continue
    id="$(sed -n 1p "$f")"
    [ -d "$id" ] || { rm -f "$f"; continue; }               # dead worktree/cwd → orphan
    ts="$(sed -n 3p "$f")"; case "$ts" in ''|*[!0-9]*) ts=1800 ;; esac
    age=$(( now - $(stat -f %m "$f" 2>/dev/null || echo "$now") ))
    [ "$age" -gt $(( ts * 2 )) ] && rm -f "$f"              # long past budget → stale
  done
}
```

Replace the `disarm)` case with:

```bash
  disarm)
    waits_dir="$MAIL_ROOT/.codex-waits"
    if [ "${3:-}" = "--stale" ]; then prune_stale "$waits_dir"; exit 0; fi
    [ -n "$consumer" ] || err "not inside a git worktree — mailbox waits are keyed per worktree"
    for f in "$waits_dir"/*; do
      [ -f "$f" ] || continue
      [ "$(sed -n 1p "$f")" = "$consumer" ] && rm -f "$f"
    done
    ;;
```

Update the `usage()` heredoc and header synopsis disarm line:

```
       sprint-mail.sh disarm <sprint-dir> [--stale]
```

- [ ] **Step 4: Run the full mail suite to verify it passes**

Run: `sprint-orchestrator/test/test-sprint-mail.sh`
Expected: PASS — reaper cases pass; the Task 3 arm assertions pass (arm now finds `prune_stale`); all prior cases still pass.

- [ ] **Step 5: Commit Tasks 3 + 4 together**

```bash
git add sprint-orchestrator/sprint-mail.sh sprint-orchestrator/test/test-sprint-mail.sh
git commit -m "feat(sprint): cursor-path arm record + stale/orphan reaper"
# (append the standard Co-Authored-By / Claude-Session trailers)
```

---

### Task 5: Lint pins

**Files:**
- Modify: `test/lint-skills.sh`

- [ ] **Step 1: Update the pins**

In `test/lint-skills.sh`, replace the since-epoch hook pin:

```bash
has   "stop-wait: since-epoch filter"           "since" "$CSW"
```
with the dual-reader pins:

```bash
has   "stop-wait: cursor reader"                "mode=cursor" "$CSW"
has   "stop-wait: legacy epoch reader"          "mode=epoch" "$CSW"
```

After the `"mail: disarm usage line"` pin, add:

```bash
has   "mail: disarm --stale"                    "disarm <sprint-dir> [--stale]" "$SMAIL"
has   "mail: worktree-root cursor key"          "keyed by the worktree root" "$SMAIL"
```

- [ ] **Step 2: Run the lint to verify it passes**

Run: `test/lint-skills.sh`
Expected: PASS — `mode=cursor` and `mode=epoch` are present in the rewritten hook; `disarm <sprint-dir> [--stale]` and the cursor-key comment are present in `sprint-mail.sh`.

- [ ] **Step 3: Run the whole suite**

Run each; confirm exit 0:

```bash
test/lint-skills.sh
sprint-orchestrator/test/test-sprint-mail.sh
sprint-orchestrator/test/test-codex-stop-wait.sh
sprint-orchestrator/test/test-sprint-status.sh
sprint-orchestrator/test/test-wave-handoffs.sh
sprint-orchestrator/test/test-install-codex-hook.sh
```

Expected: all green.

- [ ] **Step 4: Commit**

```bash
git add test/lint-skills.sh
git commit -m "test(sprint): pin dual-reader hook and disarm --stale"
# (append the standard Co-Authored-By / Claude-Session trailers)
```

---

## Notes for the executor

- **Task ordering:** do Task 1, then Task 2, then define `prune_stale` (Task 4 Step 3's helper) *before* running Task 3's tests, since the new `arm` calls it. The clean sequence is: Task 1 → Task 2 → Task 4 Step 3 (add `prune_stale` + `disarm --stale`) → Task 3 (rewrite `arm`) → Task 4 Steps 1–2 tests → one combined commit for Tasks 3+4 → Task 5.
- **Do not** add `--harness`, the Claude hook, or any prose — those are Phases 2–3.
- The live orphan record at `~/.sprint-mail/.codex-waits/wait-19362-1784296487` will be pruned by `prune_stale` the first time `arm` runs after this lands (its identity dir is gone); nothing else needs to touch it.
