#!/usr/bin/env bash
# codex-stop-wait.sh — Codex Stop hook: hold the turn open while an armed
# sprint-mail wait is pending for this session's cwd.
#
# Arm records are written by `sprint-mail.sh arm` (one per session cwd) under
# ${SPRINT_MAIL_ROOT:-~/.sprint-mail}/.codex-waits/, four lines: canonical
# session cwd, absolute glob(s) of the awaited mail, timeout seconds, and the
# arm epoch — only mail whose mtime is at or after that epoch wakes the turn,
# so files already processed before arming can never re-trigger.
#
# Exit 0  — no armed wait for this cwd: let the turn end normally.
# Exit 2  — stderr becomes a synthetic continuation prompt in the same thread
#           (new mail arrived, the wait timed out, or the arm state is bad).
set -u

cat > /dev/null   # drain the Stop payload; cwd comes from the process itself

WAITS_DIR="${SPRINT_MAIL_ROOT:-$HOME/.sprint-mail}/.codex-waits"
[ -d "$WAITS_DIR" ] || exit 0

cwd="$(pwd -P)"
rec=""
for f in "$WAITS_DIR"/*; do
  [ -f "$f" ] || continue
  if [ "$(sed -n 1p "$f")" = "$cwd" ]; then
    if [ -n "$rec" ]; then
      echo "codex-stop-wait: two armed waits for $cwd — run sprint-mail.sh disarm, then re-arm once." >&2
      exit 2
    fi
    rec="$f"
  fi
done
[ -n "$rec" ] || exit 0

glob="$(sed -n 2p "$rec")"
timeout="$(sed -n 3p "$rec")"
since="$(sed -n 4p "$rec")"
case "$timeout" in *[!0-9]*|'') timeout=1800 ;; esac
case "$since" in *[!0-9]*|'') since=0 ;; esac

poll="${SPRINT_MAIL_POLL:-2}"
elapsed=0
found=""
while :; do
  for f in $glob; do
    [ -e "$f" ] || continue
    [ "$(stat -f %m "$f" 2>/dev/null || echo 0)" -ge "$since" ] || continue
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
