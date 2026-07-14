#!/usr/bin/env bash
# sprint-mail.sh — transient executor↔supervisor mail for one sprint.
#
#   sprint-mail.sh post <sprint-dir> <NN> <kind> [<file>|-]
#   sprint-mail.sh list <sprint-dir> [<NN>]
#   sprint-mail.sh wait <sprint-dir> <name-or-glob> [<timeout-seconds>]
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
set -euo pipefail

MAIL_ROOT="${SPRINT_MAIL_ROOT:-$HOME/.sprint-mail}"
POLL="${SPRINT_MAIL_POLL:-20}"

usage() {
  cat >&2 <<'EOF'
usage: sprint-mail.sh post <sprint-dir> <NN> <evidence|question|concluded|reply|note> [<file>|-]
       sprint-mail.sh list <sprint-dir> [<NN>]
       sprint-mail.sh wait <sprint-dir> <name-or-glob> [<timeout-seconds>]
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
  *) usage ;;
esac
