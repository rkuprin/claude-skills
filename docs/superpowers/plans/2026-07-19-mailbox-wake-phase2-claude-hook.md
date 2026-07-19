# Mailbox wake — Phase 2: the main-session Claude Stop hook, installer, and `arm --harness`

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. **This plan is NOT subagent-safe** — Task 2 (the live interactivity gate) must run on the main interactive session's own `~/.claude/settings.json` and needs the human operator to press Esc; a subagent cannot do it. Execute inline.

**Goal:** Give an idle **main-session** Claude supervisor a real synchronous wake — `claude-stop-wait.sh` (Stop-only, dual-reader) parked by an armed record until matching unread mail lands or the budget elapses — plus `install-claude-hook.sh` (append to `Stop`, preserve co-installed hooks, no trust dance) and `arm --harness codex|claude`, all gated by a live check that Esc cleanly cancels a parked hook.

**Architecture:** `claude-stop-wait.sh` is a body-identical twin of the Phase-1 `codex-stop-wait.sh` (drain stdin → scan `.codex-waits/` → dual-read cursor/legacy → poll → `exit 2`), wired into Claude's `Stop` group instead of Codex's `hooks.json`. The two hook bodies are kept byte-identical from `set -u` onward and a lint `diff` pin enforces it — one source of truth, zero drift, without renaming the live-trusted Codex hook. `arm` takes an explicit `--harness` selector that verifies the named harness's Stop reference. The installer mirrors `install-codex-hook.sh` minus the app-server trust dance (Claude settings-json hooks activate on write).

**Tech Stack:** Bash 3.2, coreutils only (`git rev-parse`, `sed`, `grep`, `stat`, `diff`, `ls`). JSON handling in the installer uses `python3` (as `install-codex-hook.sh` does). Tests and lint are bash + `grep` (+ `diff`, `python3` for JSON assertions in the installer test only).

This is Phase 2 of the spec `docs/superpowers/specs/2026-07-19-unified-mailbox-wake-design.md`. Phase 1 (worktree-root cursor, 4-line record, dual-reader Codex hook, reaper) is merged to `main`. **Phase 3 (prose, topology-aware rendering, READMEs, INSTALL.md, EXECUTION/SKILL wording) is a separate plan — do NOT touch any `.md` skill prose, `wave-handoffs.sh`, `README.md`, or `INSTALL.md` here.**

## Global Constraints

- **Bash 3.2, coreutils only.** No `jq`, no GNU-only flags. `python3` only inside `install-claude-hook.sh` and its test (JSON), exactly as `install-codex-hook.sh` already does.
- **Both hook bodies stay byte-identical from `set -u` onward.** Only the leading header comment differs (naming the harness). A lint `diff` pin makes divergence a lint failure.
- **The Codex hook is NOT renamed or re-wired.** It is live-trusted by content hash on this machine; renaming to a shared `stop-wait.sh` would break that trust and re-litigate the spec's pinned reference strings. Rejected in favor of the body-in-sync twin. (Decision recorded in Task 1.)
- **`Stop` only — never `SubagentStop`.** No `stop_hook_active` branch (the 8-block cap resets on the supervisor's tool-work between wakes; the spike settled this).
- **The installer PRESERVES co-installed Stop hooks.** An iTerm-status `Stop` hook exists in `~/.claude/settings.json` and must survive every install/idempotent/re-point run. The installer adds its hook as its *own* new `Stop` group and never mutates an existing group's `hooks` array.
- **`arm` requires `--harness codex|claude`** immediately after `arm`. A textual reference is not proof the hook is *active* (Claude: `disableAllHooks`/managed policy; Codex: silent-skip until trusted) — `arm` verifies a reference exists in the expected place; installers own activation. Keep that honest wording.
- **`.codex-waits/` is shared** by both hooks — do NOT rename it.
- **Lint pins land in the SAME commit as the code that introduces the pinned string** (repo rule: prose is the product, lint it). No separate lint commit.
- **Every commit** ends with the standard `Co-Authored-By:` and `Claude-Session:` trailers.
- **Live-record safety (this machine):** a foreign, live wait record armed from `/Users/rkuprin/710` sits in `~/.sprint-mail/.codex-waits/`. It is not this worktree's and not stale — leave it untouched. All gate operations scope to this worktree root (`/Users/rkuprin/claude-skills`).

---

### Task 1: `claude-stop-wait.sh` — the main-session Claude Stop hook (body-identical twin)

**Decision (copy-with-sync-lint, not shared file):** the task invites factoring one shared `stop-wait.sh`. Rejected. The two scripts are byte-identical in logic, so the drift risk that motivates sharing is fully neutralized by a lint `diff` pin — without the cost of renaming the Codex hook, which is live-trusted by content hash (`install-codex-hook.sh`'s app-server dance) and whose name the 3-pass-vetted spec pins in `arm --harness codex`, both installers, and the lint. A twin named `claude-stop-wait.sh` keeps each harness's wiring self-documenting and honors the spec's named files; the `diff` pin makes logic divergence impossible to land silently.

**Files:**
- Create: `sprint-orchestrator/claude-stop-wait.sh`
- Create: `sprint-orchestrator/test/test-claude-stop-wait.sh`
- Modify: `test/lint-skills.sh` (add claude-hook pins — same commit)

**Interfaces:**
- Consumes: 4-line records under `${SPRINT_MAIL_ROOT:-~/.sprint-mail}/.codex-waits/` — new `{worktree-root, glob(s), timeout, /abs/cursor}` or legacy `{cwd, glob(s), timeout, epoch}`.
- Produces: on a `Stop` event, `exit 0` silent when no record matches this session; `exit 2` (stderr → continuation) on an unread-against-cursor match (new) / `mtime>=since` match (legacy) / budget elapse; record consumed (`rm`) on either exit-2 path.

- [ ] **Step 1: Create the hook test as a near-copy of the Codex hook test**

Create `sprint-orchestrator/test/test-claude-stop-wait.sh` — identical to `test-codex-stop-wait.sh` except the header comment and the `SUT` path. Full content:

```bash
#!/usr/bin/env bash
# Hermetic tests for claude-stop-wait.sh — the main-session Claude Stop hook that
# holds a turn open while an armed sprint-mail wait is pending. Body-identical to
# codex-stop-wait.sh (a lint diff pin enforces it); this suite mirrors
# test-codex-stop-wait.sh so both transports are proven on the same records.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SUT="$HERE/../claude-stop-wait.sh"
PASS=0; FAIL=0
ok() { PASS=$((PASS+1)); printf 'ok   - %s\n' "$1"; }
no() { FAIL=$((FAIL+1)); printf 'FAIL - %s\n' "$1"; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export SPRINT_MAIL_ROOT="$TMP/mailroot"
export SPRINT_MAIL_POLL=1
WAITS="$SPRINT_MAIL_ROOT/.codex-waits"
MDIR="$SPRINT_MAIL_ROOT/repo/sprint"
mkdir -p "$WAITS" "$MDIR" "$TMP/cwd"
git -C "$TMP/cwd" init -q
cd "$TMP/cwd"
WTROOT="$(cd "$TMP/cwd" && pwd -P)"

arm() {  # legacy record: $1=glob(s) $2=timeout $3=since-epoch  (identity = cwd)
  printf '%s\n%s\n%s\n%s\n' "$(pwd -P)" "$1" "$2" "$3" > "$WAITS/.tmp.$$" \
    && mv "$WAITS/.tmp.$$" "$WAITS/wait-t"
}
arm_cursor() {  # new record: $1=glob(s) $2=timeout $3=/abs/cursor  (identity = worktree root)
  printf '%s\n%s\n%s\n%s\n' "$WTROOT" "$1" "$2" "$3" > "$WAITS/.tmp.$$" \
    && mv "$WAITS/.tmp.$$" "$WAITS/wait-t"
}

# ---- no armed record: pass through silently ----
out="$(: | "$SUT" 2>&1)"; rc=$?
[ "$rc" = "0" ] && [ -z "$out" ] && ok "no record → exit 0, silent" || no "no record → exit 0, silent (rc=$rc out=$out)"

# ---- armed, reply arrives mid-wait: exit 2, wake message, record consumed ----
arm "$MDIR/01-001-reply.md" 30 0
( sleep 2; echo hi > "$MDIR/01-001-reply.md" ) &
out="$(: | "$SUT" 2>&1)"; rc=$?
wait
[ "$rc" = "2" ] && ok "reply arrival → exit 2" || no "reply arrival → exit 2 (rc=$rc)"
case "$out" in *"New sprint mail arrived: $MDIR/01-001-reply.md"*) ok "wake message names the file" ;; *) no "wake message names the file (got: $out)" ;; esac
[ ! -f "$WAITS/wait-t" ] && ok "record consumed on wake" || no "record consumed on wake"

# ---- timeout: exit 2 with the fallback message, record consumed ----
arm "$MDIR/01-002-reply.md" 2 0
out="$(: | "$SUT" 2>&1)"; rc=$?
[ "$rc" = "2" ] && case "$out" in *"timed out after 2s"*) true ;; *) false ;; esac \
  && ok "timeout → exit 2 with fallback message" || no "timeout → exit 2 with fallback message (rc=$rc out=$out)"
[ ! -f "$WAITS/wait-t" ] && ok "record consumed on timeout" || no "record consumed on timeout"

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

# ---- two records for one session: refuse with a remedy, keep both records ----
arm "$MDIR/x.md" 5 0
printf '%s\n%s\n%s\n%s\n' "$(pwd -P)" "$MDIR/y.md" 5 0 > "$WAITS/wait-t2"
out="$(: | "$SUT" 2>&1)"; rc=$?
[ "$rc" = "2" ] && case "$out" in *"two armed waits"*disarm*) true ;; *) false ;; esac \
  && ok "double-arm → exit 2 naming disarm" || no "double-arm → exit 2 naming disarm (rc=$rc out=$out)"
rm -f "$WAITS"/wait-*

# ---- another session's record (different identity) is not ours: pass through ----
printf '%s\n%s\n%s\n%s\n' "$TMP/elsewhere" "$MDIR/z.md" 5 0 > "$WAITS/wait-other"
out="$(: | "$SUT" 2>&1)"; rc=$?
[ "$rc" = "0" ] && ok "foreign record ignored" || no "foreign record ignored (rc=$rc)"
[ -f "$WAITS/wait-other" ] && ok "foreign record left intact" || no "foreign record left intact"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
```

Make it executable: `chmod +x sprint-orchestrator/test/test-claude-stop-wait.sh`.

- [ ] **Step 2: Run the test to verify it fails**

Run: `sprint-orchestrator/test/test-claude-stop-wait.sh`
Expected: FAIL immediately — `sprint-orchestrator/claude-stop-wait.sh` does not exist (SUT not found), so the first `"$SUT"` invocation errors and cases fail.

- [ ] **Step 3: Create `claude-stop-wait.sh` with a Claude header and a body byte-identical to the Codex hook**

Create `sprint-orchestrator/claude-stop-wait.sh`. The header (through `set -u`) is Claude-specific; **everything from `set -u` onward must be byte-identical to `codex-stop-wait.sh`** (copy it verbatim). Full content:

```bash
#!/usr/bin/env bash
# claude-stop-wait.sh — Claude Code Stop hook: hold a MAIN-session turn open
# while an armed sprint-mail wait is pending for this session.
#
# The body below (from `set -u` onward) is kept BYTE-IDENTICAL to
# codex-stop-wait.sh — a lint diff pin enforces it, so the wake logic has one
# source of truth. Only this header differs. Wired for `Stop` only, never
# SubagentStop: a blocking SubagentStop on a foreground in-session subagent
# deadlocks the parent. No stop_hook_active branch — the 8-consecutive-block cap
# resets on the supervisor's tool-work between wakes.
#
# Records live under ${SPRINT_MAIL_ROOT:-~/.sprint-mail}/.codex-waits/ (a name
# shared with the Codex hook — do not rename), four lines. Two formats coexist
# during the cursor migration (dual-reader):
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

> Note: the double-arm message intentionally still reads `codex-stop-wait:` — it is part of the byte-identical shared body. The prefix is a diagnostic label, not a harness claim; keeping it identical is what lets the `diff` pin hold. Do not "fix" it to `claude-stop-wait:` — that would fork the body and fail the sync lint.

Make it executable: `chmod +x sprint-orchestrator/claude-stop-wait.sh`.

- [ ] **Step 4: Run the hook test to verify it passes**

Run: `sprint-orchestrator/test/test-claude-stop-wait.sh`
Expected: PASS — `12 passed, 0 failed` (or whatever the case count is), all cases green.

- [ ] **Step 5: Verify the two hook bodies are byte-identical from `set -u`**

Run:
```bash
diff <(sed -n '/^set -u$/,$p' sprint-orchestrator/codex-stop-wait.sh) \
     <(sed -n '/^set -u$/,$p' sprint-orchestrator/claude-stop-wait.sh) && echo IN-SYNC
```
Expected: no diff output, prints `IN-SYNC`. If it differs, the copy drifted — fix it before continuing.

- [ ] **Step 6: Add the claude-hook lint pins (same commit)**

In `test/lint-skills.sh`, immediately after the `codex-stop-wait.sh` pin block (after the line `has "stop-wait: legacy epoch reader" "mode=epoch" "$CSW"`), add:

```bash
CLSW="$HERE/../sprint-orchestrator/claude-stop-wait.sh"
[ -x "$CLSW" ] && ok "claude-stop-wait: hook exists and is executable" || no "claude-stop-wait: hook exists and is executable"
has   "claude-stop-wait: Stop-only main sessions" "MAIN-session" "$CLSW"
has   "claude-stop-wait: silent pass without a record" "exit 0" "$CLSW"
has   "claude-stop-wait: continuation via exit 2"      "exit 2" "$CLSW"
# The two hook bodies (from `set -u` onward) must stay byte-identical: one source
# of truth for the wake logic. Only the leading harness header may differ.
if diff <(sed -n '/^set -u$/,$p' "$CSW") <(sed -n '/^set -u$/,$p' "$CLSW") >/dev/null 2>&1; then
  ok "claude-stop-wait: body in sync with codex-stop-wait"
else
  no "claude-stop-wait: body diverges from codex-stop-wait"
fi
```

- [ ] **Step 7: Run the lint to verify the new pins pass**

Run: `test/lint-skills.sh`
Expected: PASS — `N passed, 0 failed`; the four new claude-stop-wait pins and the in-sync diff pin are green.

- [ ] **Step 8: Commit**

```bash
git branch --show-current && git status --short
git add sprint-orchestrator/claude-stop-wait.sh sprint-orchestrator/test/test-claude-stop-wait.sh test/lint-skills.sh
git commit -m "feat(sprint): main-session Claude Stop hook (body twin of codex)"
# (append the standard Co-Authored-By / Claude-Session trailers)
```

---

### Task 2: The live interactivity gate (main session only — can veto the budget)

**This is a manual live validation, not a code change.** It produces a recorded result that parametrizes Task 4's installer timeout and (later) Phase 3's arm budget. It runs on the real `~/.claude/settings.json` and needs the human operator to press Esc — a subagent cannot substitute. Use SHORT timeouts throughout so a stuck hook self-frees in ≤90s even if Esc fails.

**Files:** none committed. Touches `~/.claude/settings.json` (backed up and restored) and `~/.sprint-mail/.codex-waits/` (own-identity records only).

**Pre-flight safety:**
- Back up settings: `cp ~/.claude/settings.json ~/.claude/settings.json.gate-bak`
- Record this worktree root for scoping: `WT="$(git rev-parse --show-toplevel)"; WT="$(cd "$WT" && pwd -P)"`
- Confirm no own-identity record is already armed:
  `for f in ~/.sprint-mail/.codex-waits/*; do [ -f "$f" ] && [ "$(sed -n 1p "$f")" = "$WT" ] && echo "OWN: $f"; done` — expect no output. (The foreign `/Users/rkuprin/710` record may print under its own identity check; leave it.)
- Scratch dir for the gate mailbox glob: `GATE="$(mktemp -d)"; mkdir -p "$GATE/.read"; : > "$GATE/.read/cur"`

- [ ] **Step 1: Wire the hook into settings.json with a SHORT hard timeout, preserving the iTerm hook**

Add `claude-stop-wait.sh` as its own `Stop` group with `timeout: 90` (gate-only; the real installer uses the budget timeout later). Run:

```bash
python3 - ~/.claude/settings.json "$(git rev-parse --show-toplevel)/sprint-orchestrator/claude-stop-wait.sh" <<'PY'
import json, sys
path, hook = sys.argv[1], sys.argv[2]
d = json.load(open(path))
cmd = f"bash '{hook}'"
grp = {"matcher": "", "hooks": [{"type": "command", "command": cmd, "timeout": 90,
        "statusMessage": "GATE: sprint mailbox wait"}]}
stop = d.setdefault("hooks", {}).setdefault("Stop", [])
if not any("claude-stop-wait.sh" in h.get("command","") for g in stop for h in g.get("hooks",[])):
    stop.append(grp)
json.dump(d, open(path, "w"), indent=2)
print("wired (gate, timeout 90); iterm hook present:",
      any("iterm-status/stop.sh" in h.get("command","") for g in stop for h in g.get("hooks",[])))
PY
```
Expected: `wired (gate, timeout 90); iterm hook present: True`.

**The settings.json edit auto-reloads, but the running session may need it re-read.** If the gate hook does not fire in Step 3, the operator should re-read settings (or the check is inconclusive — note it).

- [ ] **Step 2: Sub-check A — Esc interruptibility (human-required; highest veto power)**

Hand-write a parked record (own identity, a glob that will NOT be satisfied, so it parks the full 45s):

```bash
WT="$(git rev-parse --show-toplevel)"; WT="$(cd "$WT" && pwd -P)"
printf '%s\n%s\n45\n%s\n' "$WT" "$GATE/reply-*.md" "$GATE/.read/cur" \
  > ~/.sprint-mail/.codex-waits/wait-gate-esc
```

Then **end the turn** with a message to the operator: *"I've armed a 45s parked hook (hard-kill 90s). When you see the Stop hook running/spinner, press Esc. Report: did control return immediately, or only after ~45–90s?"*

Record the operator's answer:
- **Esc returns control immediately →** interruptible. The 3h (10800/10860) budget stands.
- **Control returns only at 45–90s →** Esc does NOT cancel. Drop the default idle budget to minutes; Task 4 uses a short installer timeout (e.g. `360`) and this is reported loudly.

Clean up after: `rm -f ~/.sprint-mail/.codex-waits/wait-gate-esc`.

- [ ] **Step 3: Sub-check B — two wake→work→re-arm cycles run clean (self-driven)**

Cycle 1: launch a background file-dropper, arm a short own-identity record on the gate glob, end the turn so the hook parks, and let the drop wake it:

```bash
WT="$(git rev-parse --show-toplevel)"; WT="$(cd "$WT" && pwd -P)"
( sleep 4; echo hi > "$GATE/reply-001.md" ) >/dev/null 2>&1 &   # dropper
printf '%s\n%s\n60\n%s\n' "$WT" "$GATE/reply-*.md" "$GATE/.read/cur" \
  > ~/.sprint-mail/.codex-waits/wait-gate-c1
```
End the turn → the hook parks → the dropper writes `reply-001.md` → hook wakes (`exit 2`, continuation names the file). On wake: do a real tool call (e.g. `sprint-mail.sh list` or any Read) — this is the "work" that resets the block cap — then re-arm cycle 2 with a fresh dropper (`reply-002.md`) and a new own-identity record, and end the turn again. Wake 2 must arrive without a block-cap override.

Verify after both cycles:
- Each wake's continuation named the dropped file (`reply-001.md`, then `reply-002.md`).
- The hook consumed each record on wake: `ls ~/.sprint-mail/.codex-waits/wait-gate-c* 2>/dev/null` → empty.
- No block-cap message appeared on the second wake.

- [ ] **Step 4: Sub-check C — no orphaned record on session exit/resume**

Confirm the hook consumes on wake (Step 3 already showed `wait-gate-c*` gone), and that a parked record left by an abandoned turn is drainable:

```bash
WT="$(git rev-parse --show-toplevel)"; WT="$(cd "$WT" && pwd -P)"
printf '%s\n%s\n1\n%s\n' "$WT" "$GATE/reply-*.md" "$GATE/.read/cur" \
  > ~/.sprint-mail/.codex-waits/wait-gate-orphan
touch -t 202607140000 ~/.sprint-mail/.codex-waits/wait-gate-orphan   # backdate past 2x its 1s budget
sprint-orchestrator/sprint-mail.sh disarm docs/sprints/x --stale 2>/dev/null || true
[ ! -f ~/.sprint-mail/.codex-waits/wait-gate-orphan ] && echo "orphan drained by reaper" || echo "ORPHAN SURVIVED"
```
Expected: `orphan drained by reaper`. (This exercises the Phase-1 `disarm --stale` reaper on an own-identity backdated record; `arm` also prunes it before its double-arm check.)

- [ ] **Step 5: Tear down the gate wiring — restore the original settings.json**

```bash
# remove any leftover own-identity gate records
rm -f ~/.sprint-mail/.codex-waits/wait-gate-*
# restore settings exactly as it was before the gate
cp ~/.claude/settings.json.gate-bak ~/.claude/settings.json
rm -f ~/.claude/settings.json.gate-bak
rm -rf "$GATE"
# confirm the iTerm hook is back and the gate hook is gone
grep -c 'claude-stop-wait.sh' ~/.claude/settings.json   # expect 0
grep -c 'iterm-status/stop.sh' ~/.claude/settings.json  # expect 1
```
Expected: `0` then `1`. (The real installer re-wires at the budget timeout at the very end of the plan, only if the operator wants this machine dogfooded.)

- [ ] **Step 6: Record the gate result**

Write the outcome into the plan/PR description and carry it to Task 4:
- Esc interruptible? (yes → 10860 stands; no → short timeout + loud note)
- Two cycles clean? (yes/no)
- No orphan on exit? (yes/no)

**No commit** — this task changes no tracked files.

---

### Task 3: `arm --harness codex|claude`

**Files:**
- Modify: `sprint-orchestrator/sprint-mail.sh` (top-of-file synopsis + arm-header comment; `usage()` arm line; a `--harness` extractor near the top; the `arm)` case's wiring check)
- Modify: `sprint-orchestrator/test/test-sprint-mail.sh` (add `--harness` to existing arm calls; add per-harness selection cases)
- Modify: `test/lint-skills.sh` (arm usage pin gains `--harness`; add a claude-installer-reference pin — same commit)

**Interfaces:**
- Produces: `arm --harness <codex|claude> <sprint-dir> <name-or-glob(s)> [<timeout>]`. `--harness codex` verifies `${CODEX_HOME:-~/.codex}/hooks.json` references `codex-stop-wait.sh`; `--harness claude` verifies `${CLAUDE_CONFIG_DIR:-~/.claude}/settings.json` (or `settings.local.json`) references `claude-stop-wait.sh`. Absent/invalid `--harness` → refuse. The record format and identity are unchanged from Phase 1.

- [ ] **Step 1: Update the arm tests for `--harness` (write the new expectations first)**

In `sprint-orchestrator/test/test-sprint-mail.sh`, replace the whole arm/disarm block (from the comment `# ---- arm/disarm: cwd-keyed reactive-wait records for the Codex Stop hook ----` through the line `  && no "non-numeric timeout rejected" || ok "non-numeric timeout rejected"`) with:

```bash
# ---- arm/disarm: --harness selects which harness's Stop reference gates the arm ----
# arm refuses when the named harness's hook is not referenced (a record nothing
# consumes is a dead wait); give the fixture a wired CODEX_HOME first.
export CODEX_HOME="$TMP/codexhome"
mkdir -p "$CODEX_HOME"
out="$("$SUT" arm --harness codex "$SPRINT" "07-009-reply.md" 900 2>&1)"; rc=$?
[ "$rc" = "2" ] && case "$out" in *install-codex-hook.sh*) true ;; *) false ;; esac \
  && ok "arm --harness codex refused without a wired hook, names the codex installer" \
  || no "arm --harness codex refused without a wired hook, names the codex installer (rc=$rc out=$out)"
printf '{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"bash codex-stop-wait.sh"}]}]}}\n' > "$CODEX_HOME/hooks.json"
WAITS="$SPRINT_MAIL_ROOT/.codex-waits"
rec="$("$SUT" arm --harness codex "$SPRINT" "07-009-reply.md" 900)"
[ -f "$rec" ] && ok "arm writes a record and prints its path" || no "arm writes a record and prints its path (got: $rec)"
[ "$(sed -n 1p "$rec")" = "$(cd "$REPO_A" && pwd -P)" ] && ok "arm line 1 is the worktree root" || no "arm line 1 is the worktree root"
[ "$(sed -n 2p "$rec")" = "$MDIR/07-009-reply.md" ] && ok "arm line 2 is the absolute mailbox glob" || no "arm line 2 is the absolute mailbox glob (got: $(sed -n 2p "$rec"))"
[ "$(sed -n 3p "$rec")" = "900" ] && ok "arm line 3 is the timeout" || no "arm line 3 is the timeout"
case "$(sed -n 4p "$rec")" in "$MDIR/.read/"*) ok "arm line 4 is the cursor path" ;; *) no "arm line 4 is the cursor path (got: $(sed -n 4p "$rec"))" ;; esac
"$SUT" arm --harness codex "$SPRINT" "07-010-reply.md" 900 >/dev/null 2>&1 \
  && no "second arm for same worktree rejected" || ok "second arm for same worktree rejected"
"$SUT" disarm "$SPRINT"
[ ! -f "$rec" ] && ok "disarm removes this worktree's record" || no "disarm removes this worktree's record"
"$SUT" arm --harness codex "$SPRINT" "07-*-reply.md 07-*-note.md" 900 >/dev/null \
  && rec2="$(ls "$WAITS"/wait-* 2>/dev/null | head -1)" \
  && [ "$(sed -n 2p "$rec2")" = "$MDIR/07-*-reply.md $MDIR/07-*-note.md" ] \
  && case "$(sed -n 4p "$rec2")" in "$MDIR/.read/"*) true ;; *) false ;; esac \
  && ok "arm accepts multiple globs unexpanded, line 4 is the cursor path" \
  || no "arm accepts multiple globs unexpanded, line 4 is the cursor path"
"$SUT" disarm "$SPRINT"

# --harness claude verifies the Claude settings reference instead of the Codex one.
# A wired Claude settings lets --harness claude proceed even with the Codex hook
# unwired; --harness codex still refuses in that state.
rm -f "$CODEX_HOME/hooks.json"
export CLAUDE_CONFIG_DIR="$TMP/claudehome"
mkdir -p "$CLAUDE_CONFIG_DIR"
printf '{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"bash claude-stop-wait.sh"}]}]}}\n' > "$CLAUDE_CONFIG_DIR/settings.json"
rec_cl="$("$SUT" arm --harness claude "$SPRINT" "07-011-reply.md" 900)"
[ -f "$rec_cl" ] && ok "arm --harness claude proceeds with wired Claude settings, no Codex hook" || no "arm --harness claude proceeds with wired Claude settings (got: $rec_cl)"
"$SUT" disarm "$SPRINT"
out="$("$SUT" arm --harness codex "$SPRINT" "07-011-reply.md" 900 2>&1)"; rc=$?
[ "$rc" = "2" ] && case "$out" in *install-codex-hook.sh*) true ;; *) false ;; esac \
  && ok "arm --harness codex still refuses when only Claude is wired" \
  || no "arm --harness codex still refuses when only Claude is wired (rc=$rc out=$out)"
# restore the Codex wiring for the reaper cases below
printf '{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"bash codex-stop-wait.sh"}]}]}}\n' > "$CODEX_HOME/hooks.json"

# arm requires --harness; a bare arm is refused naming the flag.
out="$("$SUT" arm "$SPRINT" "07-009-reply.md" 900 2>&1)"; rc=$?
[ "$rc" = "2" ] && case "$out" in *"--harness"*) true ;; *) false ;; esac \
  && ok "arm without --harness refused, names the flag" || no "arm without --harness refused (rc=$rc out=$out)"

"$SUT" arm --harness codex "$SPRINT" "sub/dir.md" 900 >/dev/null 2>&1 \
  && no "path-shaped pattern rejected" || ok "path-shaped pattern rejected"
"$SUT" arm --harness codex "$SPRINT" "07-009-reply.md" "soon" >/dev/null 2>&1 \
  && no "non-numeric timeout rejected" || ok "non-numeric timeout rejected"
```

Then update the two reaper-case `arm` calls further down to pass `--harness codex` (they run with `CODEX_HOME` wired from the restore above). In the block `# ---- reaper: arm prunes a dead-identity record before its double-arm check ----`, change:
```bash
"$SUT" arm "$SPRINT" "07-050-reply.md" 900 >/dev/null
```
to:
```bash
"$SUT" arm --harness codex "$SPRINT" "07-050-reply.md" 900 >/dev/null
```
(The `disarm --stale` reaper case needs no `arm` and is unchanged.)

- [ ] **Step 2: Run the mail suite to verify it fails**

Run: `sprint-orchestrator/test/test-sprint-mail.sh`
Expected: FAIL — the current `arm` does not accept `--harness` (it treats `--harness` as `sprint_dir`), so the new cases error and the refusal/selection assertions fail.

- [ ] **Step 3: Add the `--harness` extractor near the top of `sprint-mail.sh`**

In `sprint-orchestrator/sprint-mail.sh`, replace the two lines:
```bash
cmd="${1:-}"; sprint_dir="${2:-}"
[ -n "$cmd" ] && [ -n "$sprint_dir" ] || usage
```
with:
```bash
cmd="${1:-}"
# `arm` takes a required --harness <codex|claude> immediately after the command
# (the kickoff always knows the target harness). Pull it out before positional
# parsing so sprint-dir/glob/timeout stay positional exactly like every other
# subcommand.
harness=""
if [ "$cmd" = "arm" ] && [ "${2:-}" = "--harness" ]; then
  harness="${3:-}"
  case "$harness" in
    codex|claude) ;;
    *) err "arm --harness needs 'codex' or 'claude' (got: ${harness:-<empty>})" ;;
  esac
  shift 3; set -- arm "$@"
fi
sprint_dir="${2:-}"
[ -n "$cmd" ] && [ -n "$sprint_dir" ] || usage
```
(`err` and `usage` are already defined above this line, so they are callable here.)

- [ ] **Step 4: Replace the `arm)` wiring check with the per-harness check**

In the `arm)` case, replace this block:
```bash
    [ -n "$consumer" ] || err "not inside a git worktree — mailbox waits are keyed per worktree; run from the project worktree"
    # An armed record only works if the Stop hook is wired — otherwise the turn
    # ends and nothing ever wakes, the exact orphaned-wait failure arm exists to
    # prevent. Refuse loudly instead of arming a dead wait.
    hooks_json="${CODEX_HOME:-$HOME/.codex}/hooks.json"
    grep -q "codex-stop-wait.sh" "$hooks_json" 2>/dev/null \
      || err "codex Stop hook not wired in $hooks_json — run sprint-orchestrator/install-codex-hook.sh once on this machine, or take the contract's no-wait fallback instead of arming"
```
with:
```bash
    [ -n "$harness" ] || err "arm requires --harness <codex|claude> immediately after 'arm' — the kickoff names the target harness"
    [ -n "$consumer" ] || err "not inside a git worktree — mailbox waits are keyed per worktree; run from the project worktree"
    # An armed record only works if the named harness's Stop hook is wired —
    # otherwise the turn ends and nothing ever wakes, the exact orphaned-wait
    # failure arm exists to prevent. A textual reference is NOT proof the hook is
    # active (Claude: disableAllHooks / managed policy; Codex: silent-skip until
    # trusted) — the installers own activation; arm only verifies the reference
    # exists in the expected place. Refuse loudly instead of arming a dead wait.
    case "$harness" in
      codex)
        ref="${CODEX_HOME:-$HOME/.codex}/hooks.json"
        grep -q "codex-stop-wait.sh" "$ref" 2>/dev/null \
          || err "codex Stop hook not referenced in $ref — run sprint-orchestrator/install-codex-hook.sh once on this machine, or take the contract's no-wait fallback instead of arming" ;;
      claude)
        cfg="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
        grep -q "claude-stop-wait.sh" "$cfg/settings.json" "$cfg/settings.local.json" 2>/dev/null \
          || err "claude Stop hook not referenced in $cfg/settings.json — run sprint-orchestrator/install-claude-hook.sh once on this machine, or take the contract's no-wait fallback instead of arming" ;;
    esac
```

- [ ] **Step 5: Update the usage line and the two synopsis comments**

In `sprint-orchestrator/sprint-mail.sh`, in the `usage()` heredoc, change:
```
       sprint-mail.sh arm <sprint-dir> <name-or-glob(s)> [<timeout-seconds>]
```
to:
```
       sprint-mail.sh arm --harness <codex|claude> <sprint-dir> <name-or-glob(s)> [<timeout-seconds>]
```
In the top-of-file synopsis comment, change the `arm` line the same way:
```
#   sprint-mail.sh arm --harness <codex|claude> <sprint-dir> <name-or-glob(s)> [<timeout-seconds>]
```
And update the `arm` header paragraph (the comment block beginning `# \`arm\` registers a reactive wait for the Codex Stop hook (codex-stop-wait.sh):`) to name both hooks and the selector:
```
# `arm --harness codex|claude` registers a reactive wait for that harness's Stop
# hook (codex-stop-wait.sh / claude-stop-wait.sh): one record per worktree under
# $MAIL_ROOT/.codex-waits/, four lines — worktree root, absolute glob(s), timeout,
# absolute cursor path. `--harness` selects which harness's Stop reference must
# already exist (a reference is not proof the hook is active — installers own
# that). `disarm` removes this worktree's record.
```

- [ ] **Step 6: Run the mail suite to verify it passes**

Run: `sprint-orchestrator/test/test-sprint-mail.sh`
Expected: PASS — all arm/harness/reaper cases green, `N passed, 0 failed`.

- [ ] **Step 7: Update the lint pins (same commit)**

In `test/lint-skills.sh`, change the arm usage pin:
```bash
has   "mail: arm usage line"                    "arm <sprint-dir> <name-or-glob(s)>" "$SMAIL"
```
to:
```bash
has   "mail: arm usage line"                    "arm --harness <codex|claude> <sprint-dir> <name-or-glob(s)>" "$SMAIL"
```
And immediately after the existing `has "mail: arm refuses without wired hook" "install-codex-hook.sh" "$SMAIL"` line, add:
```bash
has   "mail: arm claude branch names installer" "install-claude-hook.sh" "$SMAIL"
has   "mail: arm requires --harness"            "arm requires --harness" "$SMAIL"
```

- [ ] **Step 8: Run the lint and the full suite to verify green**

Run each; confirm exit 0:
```bash
test/lint-skills.sh
sprint-orchestrator/test/test-sprint-mail.sh
sprint-orchestrator/test/test-codex-stop-wait.sh
sprint-orchestrator/test/test-claude-stop-wait.sh
```
Expected: all green.

- [ ] **Step 9: Commit**

```bash
git branch --show-current && git status --short
git add sprint-orchestrator/sprint-mail.sh sprint-orchestrator/test/test-sprint-mail.sh test/lint-skills.sh
git commit -m "feat(sprint): arm --harness codex|claude selector"
# (append the standard Co-Authored-By / Claude-Session trailers)
```

---

### Task 4: `install-claude-hook.sh` — wire the hook into Claude settings (no trust dance)

**Budget note:** use `timeout: 10860` throughout **iff Task 2's Esc sub-check passed**. If Esc did NOT interrupt cleanly, substitute the short budget the gate settled on (e.g. `360`) in the installer, its test, and the lint pin, and note it in the commit body.

**Files:**
- Create: `sprint-orchestrator/install-claude-hook.sh`
- Create: `sprint-orchestrator/test/test-install-claude-hook.sh`
- Modify: `test/lint-skills.sh` (claude-installer pins — same commit)

**Interfaces:**
- Produces: a machine-setup script that appends `claude-stop-wait.sh` as its own `Stop` group in `${CLAUDE_CONFIG_DIR:-~/.claude}/settings.json` with `timeout: 10860`, idempotent, preserving all existing groups and keys. No `codex` CLI, no `config.toml`, no app-server.

- [ ] **Step 1: Write the installer test first**

Create `sprint-orchestrator/test/test-install-claude-hook.sh`. Full content:

```bash
#!/usr/bin/env bash
# Hermetic tests for install-claude-hook.sh — fresh-machine wiring, idempotency,
# stale-path repointing, and preservation of a co-installed Stop hook. No trust
# dance (Claude settings-json hooks activate on write), so no codex stub is needed.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SUT="$HERE/../install-claude-hook.sh"
S="" # settings path, set below
PASS=0; FAIL=0
ok() { PASS=$((PASS+1)); printf 'ok   - %s\n' "$1"; }
no() { FAIL=$((FAIL+1)); printf 'FAIL - %s\n' "$1"; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export CLAUDE_CONFIG_DIR="$TMP/claudehome"
mkdir -p "$CLAUDE_CONFIG_DIR"
S="$CLAUDE_CONFIG_DIR/settings.json"

# seed a pre-existing, unrelated Stop hook (the iTerm status hook) + other keys
cat > "$S" <<'JSON'
{
  "model": "opus",
  "hooks": {
    "Stop": [
      { "matcher": "", "hooks": [ { "type": "command", "command": "bash ~/.claude/hooks/iterm-status/stop.sh" } ] }
    ]
  }
}
JSON

# ---- fresh install: wires Stop, preserves the iTerm hook and unrelated keys ----
out="$("$SUT" 2>&1)"; rc=$?
[ "$rc" = "0" ] && ok "install exits 0" || { no "install exits 0 (rc=$rc)"; printf '%s\n' "$out"; }
grep -q "claude-stop-wait.sh" "$S" && ok "settings.json gains the hook entry" || no "settings.json gains the hook entry"
grep -q '"timeout": 10860' "$S" && ok "entry carries the 10860s timeout" || no "entry carries the 10860s timeout"
grep -q "iterm-status/stop.sh" "$S" && ok "pre-existing iTerm Stop hook preserved" || no "pre-existing iTerm Stop hook preserved"
grep -q '"model": "opus"' "$S" && ok "unrelated settings keys preserved" || no "unrelated settings keys preserved"
case "$out" in *"entry added"*) ok "reports entry added" ;; *) no "reports entry added (got: $out)" ;; esac
if python3 - "$S" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
cmds = [h["command"] for g in d["hooks"]["Stop"] for h in g["hooks"]]
assert any("iterm-status/stop.sh" in c for c in cmds), cmds
assert any("claude-stop-wait.sh" in c for c in cmds), cmds
PY
then ok "both Stop hooks coexist in valid JSON"; else no "both Stop hooks coexist in valid JSON"; fi

# ---- second run: idempotent, no duplicate ----
out="$("$SUT" 2>&1)"; rc=$?
[ "$rc" = "0" ] && ok "second run exits 0" || no "second run exits 0 (rc=$rc)"
case "$out" in *"already present"*) ok "second run is idempotent" ;; *) no "second run idempotent (got: $out)" ;; esac
n="$(grep -c 'claude-stop-wait.sh' "$S")"
[ "$n" = "1" ] && ok "hook entry written exactly once" || no "hook entry written exactly once (got: $n)"

# ---- moved clone: stale path re-pointed, iTerm hook still preserved ----
python3 - "$S" <<'PY'
import json, sys
p = sys.argv[1]; d = json.load(open(p))
for g in d["hooks"]["Stop"]:
    for h in g["hooks"]:
        if "claude-stop-wait.sh" in h["command"]:
            h["command"] = "bash '/old/clone/sprint-orchestrator/claude-stop-wait.sh'"
json.dump(d, open(p, "w"), indent=2)
PY
out="$("$SUT" 2>&1)"
case "$out" in *"re-pointed"*) ok "stale path re-pointed at this clone" ;; *) no "stale path re-pointed (got: $out)" ;; esac
grep -q "$HERE/../claude-stop-wait.sh\|claude-skills/sprint-orchestrator/claude-stop-wait.sh" "$S" \
  && ok "re-pointed command names this clone" || no "re-pointed command names this clone"
grep -q "iterm-status/stop.sh" "$S" && ok "iTerm hook still preserved after re-point" || no "iTerm hook still preserved after re-point"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
```

Make it executable: `chmod +x sprint-orchestrator/test/test-install-claude-hook.sh`.

- [ ] **Step 2: Run the installer test to verify it fails**

Run: `sprint-orchestrator/test/test-install-claude-hook.sh`
Expected: FAIL — `install-claude-hook.sh` does not exist yet.

- [ ] **Step 3: Create `install-claude-hook.sh`**

Create `sprint-orchestrator/install-claude-hook.sh`. Full content:

```bash
#!/usr/bin/env bash
# install-claude-hook.sh — wire the sprint mailbox Stop hook into Claude Code.
#
# Idempotent, once per machine. Appends claude-stop-wait.sh as its OWN Stop group
# in ${CLAUDE_CONFIG_DIR:-~/.claude}/settings.json, PRESERVING any co-installed
# Stop hooks (an iTerm-status Stop hook is present on this machine and must
# survive) — existing groups are never mutated.
#
# No trust dance (unlike install-codex-hook.sh): Claude settings-json hooks
# activate on write — user-settings edits auto-reload; a session restart is the
# fallback. timeout 10860 = the 3h idle-wait budget (10800) plus 60s slack.
#
# Honest limit: a settings.json reference is not proof the hook RUNS — managed
# policy or `disableAllHooks` can suppress it. Those are reported, not silently
# worked around.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
HOOK="$HERE/claude-stop-wait.sh"
CFG_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
SETTINGS="$CFG_DIR/settings.json"
MANUAL="see the manual steps in sprint-orchestrator/README.md ('Reactive waits on Claude')"

command -v python3 >/dev/null 2>&1 \
  || { echo "install-claude-hook: python3 required for JSON handling; $MANUAL" >&2; exit 2; }
[ -x "$HOOK" ] || { echo "install-claude-hook: missing or non-executable $HOOK" >&2; exit 2; }
[ -d "$CFG_DIR" ] \
  || { echo "install-claude-hook: $CFG_DIR does not exist — run claude once first; $MANUAL" >&2; exit 2; }

python3 - "$SETTINGS" "$HOOK" <<'PY'
import json, os, sys
path, hook = sys.argv[1], sys.argv[2]
cmd = f"bash '{hook}'"
entry = {"type": "command", "command": cmd, "timeout": 10860,
         "statusMessage": "Waiting for sprint mailbox reply"}
data = {}
if os.path.exists(path):
    with open(path) as f:
        data = json.load(f)
groups = data.setdefault("hooks", {}).setdefault("Stop", [])
for g in groups:
    for h in g.get("hooks", []):
        if "claude-stop-wait.sh" in h.get("command", ""):
            if h.get("command") == cmd and h.get("timeout") == 10860:
                print("settings.json: entry already present")
            else:
                h.update(entry)
                with open(path, "w") as f:
                    json.dump(data, f, indent=2)
                print("settings.json: entry re-pointed at this clone")
            sys.exit(0)
groups.append({"matcher": "", "hooks": [entry]})   # own group — never mutate a co-installed one
with open(path, "w") as f:
    json.dump(data, f, indent=2)
print("settings.json: entry added")
PY

echo "install-claude-hook: done — hook wired in $SETTINGS."
echo "Running Claude sessions pick up settings-json hook edits automatically; a restart is the fallback."
echo "If hooks are disabled (disableAllHooks / managed policy), this reference will not fire until that is lifted."
```

Make it executable: `chmod +x sprint-orchestrator/install-claude-hook.sh`.

- [ ] **Step 4: Run the installer test to verify it passes**

Run: `sprint-orchestrator/test/test-install-claude-hook.sh`
Expected: PASS — `N passed, 0 failed`.

- [ ] **Step 5: Add the claude-installer lint pins (same commit)**

In `test/lint-skills.sh`, immediately after the codex installer pins (`has "installer: verifies trust, not just wiring" ...`), add:

```bash
CLINSTALLER="$HERE/../sprint-orchestrator/install-claude-hook.sh"
[ -x "$CLINSTALLER" ] && ok "claude installer: exists and is executable" || no "claude installer: exists and is executable"
has   "claude installer: preserves co-installed hooks" "PRESERVING any co-installed" "$CLINSTALLER"
has   "claude installer: 10860 timeout"                '"timeout": 10860' "$CLINSTALLER"
has   "claude installer: no trust dance"               "No trust dance" "$CLINSTALLER"
```

- [ ] **Step 6: Run the lint and the whole suite**

Run each; confirm exit 0:
```bash
test/lint-skills.sh
sprint-orchestrator/test/test-sprint-mail.sh
sprint-orchestrator/test/test-codex-stop-wait.sh
sprint-orchestrator/test/test-claude-stop-wait.sh
sprint-orchestrator/test/test-install-claude-hook.sh
sprint-orchestrator/test/test-install-codex-hook.sh
sprint-orchestrator/test/test-sprint-status.sh
sprint-orchestrator/test/test-wave-handoffs.sh
codex/test/test.sh
```
Expected: all green.

- [ ] **Step 7: Commit**

```bash
git branch --show-current && git status --short
git add sprint-orchestrator/install-claude-hook.sh sprint-orchestrator/test/test-install-claude-hook.sh test/lint-skills.sh
git commit -m "feat(sprint): install-claude-hook.sh wires the Stop hook"
# (append the standard Co-Authored-By / Claude-Session trailers)
```

---

### Task 5: Full-suite green + finish the branch

**Files:** none (verification + integration).

- [ ] **Step 1: Run every suite once more from a clean tree**

```bash
test/lint-skills.sh
sprint-orchestrator/test/test-sprint-mail.sh
sprint-orchestrator/test/test-codex-stop-wait.sh
sprint-orchestrator/test/test-claude-stop-wait.sh
sprint-orchestrator/test/test-install-claude-hook.sh
sprint-orchestrator/test/test-install-codex-hook.sh
sprint-orchestrator/test/test-sprint-status.sh
sprint-orchestrator/test/test-wave-handoffs.sh
codex/test/test.sh
```
Expected: all nine green. Any failure → fix before finishing.

- [ ] **Step 2: (Optional) dogfood-install on this machine if the gate passed**

Only if Task 2's Esc sub-check passed and the operator wants this machine wired for real:
```bash
cp ~/.claude/settings.json ~/.claude/settings.json.pre-install-bak
sprint-orchestrator/install-claude-hook.sh
grep -c 'claude-stop-wait.sh' ~/.claude/settings.json   # expect 1
grep -c 'iterm-status/stop.sh' ~/.claude/settings.json  # expect 1
```
This is an environment change, not a repo change — confirm with the operator first.

- [ ] **Step 3: Finish the development branch**

Use `superpowers:finishing-a-development-branch`. The earlier phases were merged to `main` locally and left unpushed — mirror that (merge to `main` locally, do not push unless asked).

---

## Notes for the executor

- **Do NOT touch Phase-3 files:** no `SKILL.md`, `EXECUTION.md`, `wave-handoffs.sh`, `README.md`, `INSTALL.md` prose, and no topology-aware rendering. Those lint pins (Claude subagent kickoff has no `arm --harness claude`, EXECUTION/SKILL arm-and-end-turn wording, renderer Claude form, README/INSTALL naming the Claude hook) belong to Phase 3.
- **The install-time reaper sweep from spec §2/§6 is deliberately omitted from `install-claude-hook.sh`.** Conscious deviation: routing a sweep through `sprint-mail.sh disarm … --stale` drags in `repo_name`/sprint-dir semantics that a machine-setup script has no business requiring, and the Phase-1 reaper already drains orphans on the next `arm` (and `disarm --stale`). A lingering orphan is a foreign record — the hook ignores it (pass-through), so it is harmless until reaped. The live gate's first `arm`/`disarm --stale` exercises exactly that path. If a reviewer insists on the install-time sweep, add it as a follow-up; it is not on the correctness path.
- **Task ordering is strict:** Task 1 (hook) must precede Task 2 (gate needs the hook); Task 2 must precede Task 4 (its Esc result sets the installer timeout). Task 3 is independent of the gate and may run before or after Task 2, but keep it before Task 4 so the full suite at Task 4 Step 6 includes `--harness`.
- **Gate hygiene:** always back up `~/.claude/settings.json` before editing it, scope every `.codex-waits/` operation to this worktree root, use SHORT timeouts (≤90s), and restore settings.json at the end of Task 2. Never delete the foreign `/Users/rkuprin/710` record.
```
