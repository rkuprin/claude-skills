#!/usr/bin/env bash
# Hermetic tests for codex-stop-wait.sh — the Codex Stop hook that holds a turn
# open while an armed sprint-mail wait is pending. Validated live 2026-07-17
# against codex exec and Codex Desktop 0.144.x (stderr on exit 2 becomes a
# synthetic continuation prompt in the same thread).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SUT="$HERE/../codex-stop-wait.sh"
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
cd "$TMP/cwd"

arm() {  # $1=glob(s)  $2=timeout  $3=since
  printf '%s\n%s\n%s\n%s\n' "$(pwd -P)" "$1" "$2" "$3" > "$WAITS/.tmp.$$" \
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

# ---- since-epoch: mail older than the arm never wakes the turn ----
echo old > "$MDIR/02-001-question.md"
arm "$MDIR/02-*-question.md" 2 "$(( $(stat -f %m "$MDIR/02-001-question.md") + 1 ))"
out="$(: | "$SUT" 2>&1)"
case "$out" in *"timed out"*) ok "pre-arm mail is filtered by since-epoch" ;; *) no "pre-arm mail is filtered by since-epoch (got: $out)" ;; esac

# ---- since-epoch: newer mail matching the same glob does wake it ----
arm "$MDIR/02-*-question.md" 30 "$(stat -f %m "$MDIR/02-001-question.md")"
( sleep 2; echo new > "$MDIR/02-002-question.md" ) &
out="$(: | "$SUT" 2>&1)"; rc=$?
wait
case "$out" in *"02-"*"question.md"*) ok "new mail on a glob wakes the turn" ;; *) no "new mail on a glob wakes the turn (got: $out)" ;; esac

# ---- two records for one cwd: refuse with a remedy, keep both records ----
arm "$MDIR/x.md" 5 0
printf '%s\n%s\n%s\n%s\n' "$(pwd -P)" "$MDIR/y.md" 5 0 > "$WAITS/wait-t2"
out="$(: | "$SUT" 2>&1)"; rc=$?
[ "$rc" = "2" ] && case "$out" in *"two armed waits"*disarm*) true ;; *) false ;; esac \
  && ok "double-arm → exit 2 naming disarm" || no "double-arm → exit 2 naming disarm (rc=$rc out=$out)"
rm -f "$WAITS"/wait-*

# ---- another session's record (different cwd) is not ours: pass through ----
printf '%s\n%s\n%s\n%s\n' "$TMP/elsewhere" "$MDIR/z.md" 5 0 > "$WAITS/wait-other"
out="$(: | "$SUT" 2>&1)"; rc=$?
[ "$rc" = "0" ] && ok "foreign cwd record ignored" || no "foreign cwd record ignored (rc=$rc)"
[ -f "$WAITS/wait-other" ] && ok "foreign record left intact" || no "foreign record left intact"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
