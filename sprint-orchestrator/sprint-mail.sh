#!/usr/bin/env bash
# sprint-mail.sh — transient executor↔supervisor mail for one sprint.
#
#   sprint-mail.sh post <sprint-dir> <NN> <kind> [<file>|-]
#   sprint-mail.sh list <sprint-dir> [<NN>]
#   sprint-mail.sh wait <sprint-dir> <name-or-glob> [<timeout-seconds>]
#   sprint-mail.sh arm <sprint-dir> <name-or-glob(s)> [<timeout-seconds>] [<since-epoch>]
#   sprint-mail.sh disarm <sprint-dir>
#
# Mail lives in ${SPRINT_MAIL_ROOT:-~/.sprint-mail}/<repo-basename>/<sprint-basename>/
# — outside every worktree. It is NEVER state: story state stays git-derived
# (sprint-status.sh never reads it). Files are NN-SSS-<kind>.md, append-only.
#
# Sequences are split by sender, so allocation needs no locks (bash 3.2, no flock):
#   executor counter: evidence | question | concluded
#   reply:            reuses the story's newest unanswered question's SSS
#   supervisor:       note (own counter)
# `concluded` bodies must open with:  outcome: merged|pr-ready|handback|blocked|failed|dossier
#
# `arm` registers a reactive wait for the Codex Stop hook (codex-stop-wait.sh):
# one record per session cwd under $MAIL_ROOT/.codex-waits/, four lines —
# cwd, absolute glob(s), timeout, since-epoch (defaults to now: only mail
# newer than the arm wakes the turn). `disarm` removes this cwd's record.
set -euo pipefail

MAIL_ROOT="${SPRINT_MAIL_ROOT:-$HOME/.sprint-mail}"
POLL="${SPRINT_MAIL_POLL:-20}"

usage() {
  cat >&2 <<'EOF'
usage: sprint-mail.sh post <sprint-dir> <NN> <evidence|question|concluded|reply|note> [<file>|-]
       sprint-mail.sh list <sprint-dir> [<NN>]
       sprint-mail.sh wait <sprint-dir> <name-or-glob> [<timeout-seconds>]
       sprint-mail.sh arm <sprint-dir> <name-or-glob(s)> [<timeout-seconds>] [<since-epoch>]
       sprint-mail.sh disarm <sprint-dir>
EOF
  exit 2
}
err() { echo "sprint-mail: $1" >&2; exit 2; }

cmd="${1:-}"; sprint_dir="${2:-}"
[ -n "$cmd" ] && [ -n "$sprint_dir" ] || usage

repo_name() {
  local common
  common="$(git rev-parse --git-common-dir 2>/dev/null)" \
    || err "not inside a git repo — run from the project so the mailbox can be namespaced by repo"
  common="$(cd "$common" && pwd)"
  basename "$(dirname "$common")"
}
repo="$(repo_name)"
mail_dir="$MAIL_ROOT/$repo/$(basename "$sprint_dir")"

next_seq() {  # $1=story  $2=ERE matching the kinds sharing this counter
  local max
  max="$(ls "$mail_dir" 2>/dev/null \
    | sed -n -E "s/^$1-([0-9]{3})-($2)\.md\$/\1/p" | sort -n | tail -1)"
  printf '%03d' "$(( 10#${max:-0} + 1 ))"
}

case "$cmd" in
  post)
    nn="${3:-}"; kind="${4:-}"; src="${5:--}"
    [ -n "$nn" ] && [ -n "$kind" ] || usage
    echo "$nn" | grep -qE '^[0-9]+[a-z]?$' || err "story must look like 07 or 06b (got: $nn)"
    [ "$src" = "-" ] || [ -f "$src" ] || err "cannot read message body: $src — pass an existing file or - for stdin"
    body="$(if [ "$src" = "-" ]; then cat; else cat "$src"; fi)"
    case "$kind" in
      evidence|question|concluded)
        if [ "$kind" = "concluded" ]; then
          printf '%s\n' "$body" | head -1 \
            | grep -qE '^outcome: (merged|pr-ready|handback|blocked|failed|dossier)$' \
            || err "a concluded message must open with 'outcome: merged|pr-ready|handback|blocked|failed|dossier'"
        fi
        seq="$(mkdir -p "$mail_dir"; next_seq "$nn" 'evidence|question|concluded')" ;;
      reply)
        mkdir -p "$mail_dir"
        seq="$(ls "$mail_dir" 2>/dev/null \
          | sed -n -E "s/^$nn-([0-9]{3})-question\.md\$/\1/p" | sort -n \
          | while read -r s; do [ -e "$mail_dir/$nn-$s-reply.md" ] || echo "$s"; done | tail -1)"
        [ -n "$seq" ] || err "no open question for story $nn — a reply answers one"
        ;;
      note)
        seq="$(mkdir -p "$mail_dir"; next_seq "$nn" 'note')" ;;
      *) err "unknown kind: $kind" ;;
    esac
    out="$mail_dir/$nn-$seq-$kind.md"
    tmp="$mail_dir/.tmp.$$"
    printf '%s\n' "$body" > "$tmp" && mv "$tmp" "$out"
    printf '%s\n' "$out"
    ;;
  list)
    nn="${3:-}"
    [ -d "$mail_dir" ] || exit 0
    ls -tr "$mail_dir" | grep -E "^${nn:-[0-9]+[a-z]?}-[0-9]{3}-" \
      | sed "s|^|$mail_dir/|" || true
    ;;
  wait)
    pat="${3:-}"; timeout="${4:-1800}"
    [ -n "$pat" ] || usage
    elapsed=0
    while :; do
      for f in "$mail_dir"/$pat; do
        [ -e "$f" ] && { printf '%s\n' "$f"; exit 0; }
      done
      [ "$elapsed" -ge "$timeout" ] && exit 1
      sleep "$POLL"; elapsed=$((elapsed + POLL))
    done
    ;;
  arm)
    pat="${3:-}"; timeout="${4:-1800}"; since="${5:-}"
    [ -n "$pat" ] || usage
    # An armed record only works if the Stop hook is wired — otherwise the turn
    # ends and nothing ever wakes, the exact orphaned-wait failure arm exists to
    # prevent. Refuse loudly instead of arming a dead wait.
    hooks_json="${CODEX_HOME:-$HOME/.codex}/hooks.json"
    grep -q "codex-stop-wait.sh" "$hooks_json" 2>/dev/null \
      || err "codex Stop hook not wired in $hooks_json — run sprint-orchestrator/install-codex-hook.sh once on this machine, or take the contract's no-wait fallback instead of arming"
    echo "$timeout" | grep -qE '^[0-9]+$' || err "timeout must be whole seconds (got: $timeout)"
    if [ -n "$since" ]; then
      echo "$since" | grep -qE '^[0-9]+$' || err "since must be a unix epoch (got: $since)"
    else
      since="$(date +%s)"
    fi
    case "$pat" in
      */*|*$'\n'*) err "pattern is a mail filename or glob, not a path (got: $pat)" ;;
    esac
    waits_dir="$MAIL_ROOT/.codex-waits"
    mkdir -p "$waits_dir"
    cwd="$(pwd -P)"
    for f in "$waits_dir"/*; do
      [ -f "$f" ] || continue
      [ "$(sed -n 1p "$f")" = "$cwd" ] \
        && err "a wait is already armed for $cwd — run 'sprint-mail.sh disarm' first"
    done
    abs=""
    set -f
    for p in $pat; do abs="$abs${abs:+ }$mail_dir/$p"; done
    set +f
    rec="$waits_dir/wait-$$-$(date +%s)"
    tmp="$waits_dir/.tmp.$$"
    printf '%s\n%s\n%s\n%s\n' "$cwd" "$abs" "$timeout" "$since" > "$tmp" && mv "$tmp" "$rec"
    printf '%s\n' "$rec"
    ;;
  disarm)
    waits_dir="$MAIL_ROOT/.codex-waits"
    cwd="$(pwd -P)"
    for f in "$waits_dir"/*; do
      [ -f "$f" ] || continue
      [ "$(sed -n 1p "$f")" = "$cwd" ] && rm -f "$f"
    done
    ;;
  *) usage ;;
esac
