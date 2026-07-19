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
