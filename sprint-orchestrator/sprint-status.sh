#!/usr/bin/env bash
# sprint-status.sh — derive story state from git. Nothing is stored, so nothing can drift.
#
#   DONE   a `Story: NN` trailer AND a matching `Sprint: <dir>` trailer are on the
#          same commit reachable from trunk (story numbers restart every sprint)
#   DOING  the story doc's exact `branch:` exists locally, remotely, or in a
#          worktree, and not DONE
#   TODO   neither
#
# DONE outranks DOING: merged branches and their worktrees linger.
set -euo pipefail

sprint_dir="${1:-}"
[ -n "$sprint_dir" ] || { echo "sprint-status: usage: sprint-status.sh docs/sprints/<sprint>" >&2; exit 2; }
[ -d "$sprint_dir" ] || { echo "sprint-status: no such directory: $sprint_dir — run this from the repo root and pass a sprint dir, e.g. docs/sprints/2026-07-07-report-delivery-sprint" >&2; exit 2; }

trunk="${SPRINT_TRUNK:-origin/main}"
git rev-parse --verify --quiet "$trunk^{commit}" >/dev/null \
  || { echo "sprint-status: cannot resolve trunk '$trunk' — run 'git fetch origin', or set SPRINT_TRUNK" >&2; exit 2; }

sprint_name="$(basename "$sprint_dir")"

# Escape BRE metacharacters so $num/$sprint_name are matched literally by --grep,
# never as a pattern — an unescaped `.` or `*` in a slug/sprint name would
# otherwise match trailers it has no business matching.
escape_bre() {
  local s="$1" out="" c i
  for (( i=0; i<${#s}; i++ )); do
    c="${s:i:1}"
    case "$c" in
      '.'|'*'|'['|']'|'^'|'$'|'\') out+="\\$c" ;;
      *) out+="$c" ;;
    esac
  done
  printf '%s' "$out"
}

worktree_branches="$(git worktree list --porcelain | sed -n 's|^branch refs/heads/||p')"

# Read an unquoted or singly/doubly quoted scalar from the first frontmatter
# block. Older story docs have no `branch:` and fall back to `sprint/<doc-slug>`.
story_branch() {
  awk '
    /^---[[:space:]]*$/ { if (seen) exit; seen=1; next }
    seen && /^branch:[[:space:]]*/ {
      sub(/^branch:[[:space:]]*/, "")
      sub(/[[:space:]]+#.*$/, "")
      sub(/^[[:space:]]*/, "")
      sub(/[[:space:]]*$/, "")
      print
      exit
    }
  ' "$1" | sed -E "s/^\"(.*)\"$/\1/; s/^'(.*)'$/\1/"
}

claimed_count=0
for doc in "$sprint_dir"/[0-9]*.md; do
  [ -e "$doc" ] || continue
  slug="$(basename "$doc" .md)"
  case "$slug" in *.CLAIMED) claimed_count=$((claimed_count + 1)) ;; esac
  # Legacy naming: claimed state used to be tracked via a `.CLAIMED` filename
  # suffix. State is derived from git now, so the suffix is meaningless — strip
  # it so the branch lookup (and the printed slug) match the real sprint/<slug>.
  slug="${slug%.CLAIMED}"
  case "$slug" in 00-*) continue ;; esac
  num="${slug%%-*}"
  num_pattern="$(escape_bre "$num")"
  sprint_pattern="$(escape_bre "$sprint_name")"
  branch="$(story_branch "$doc")"
  [ -n "$branch" ] || branch="sprint/$slug"

  # Story numbers restart every sprint, so `Story:` alone is not unique — require
  # the `Sprint:` trailer to match this directory's basename on the same commit.
  if [ -n "$(git log "$trunk" --all-match --grep="^Story: ${num_pattern}\$" --grep="^Sprint: ${sprint_pattern}\$" --format=%h -1)" ]; then
    state=DONE
  elif printf '%s\n' "$worktree_branches" | grep -qxF "$branch" \
    || git show-ref --verify --quiet "refs/heads/$branch" \
    || git show-ref --verify --quiet "refs/remotes/origin/$branch"; then
    state=DOING
  else
    state=TODO
  fi
  printf '%-6s %-4s %s\n' "$state" "$num" "$slug"
done

if [ "$claimed_count" -gt 0 ]; then
  if [ "$claimed_count" -eq 1 ]; then verb="doc still carries"; pronoun="it"; else verb="docs still carry"; pronoun="them"; fi
  echo "sprint-status: $claimed_count $verb the legacy .CLAIMED suffix; state is derived now — rename $pronoun to NN-slug.md" >&2
fi
