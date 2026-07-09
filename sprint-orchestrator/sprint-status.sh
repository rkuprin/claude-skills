#!/usr/bin/env bash
# sprint-status.sh — derive story state from git. Nothing is stored, so nothing can drift.
#
#   DONE   a `Story: NN` trailer is reachable from trunk
#   DOING  a sprint/NN-* branch or a worktree pinned to one exists, and not DONE
#   TODO   neither
#
# DONE outranks DOING: merged branches and their worktrees linger.
set -euo pipefail

sprint_dir="${1:-}"
[ -n "$sprint_dir" ] || { echo "sprint-status: usage: sprint-status.sh docs/sprints/<sprint>" >&2; exit 2; }
[ -d "$sprint_dir" ] || { echo "sprint-status: no such directory: $sprint_dir" >&2; exit 2; }

trunk="${SPRINT_TRUNK:-origin/main}"
git rev-parse --verify --quiet "$trunk^{commit}" >/dev/null \
  || { echo "sprint-status: cannot resolve trunk '$trunk' — run 'git fetch origin', or set SPRINT_TRUNK" >&2; exit 2; }

worktree_branches="$(git worktree list --porcelain | sed -n 's|^branch refs/heads/||p')"

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

  if [ -n "$(git log "$trunk" --grep="^Story: ${num}\$" --format=%h -1)" ]; then
    state=DONE
  elif printf '%s\n' "$worktree_branches" | grep -qx "sprint/$slug" \
    || git show-ref --verify --quiet "refs/heads/sprint/$slug" \
    || git show-ref --verify --quiet "refs/remotes/origin/sprint/$slug"; then
    state=DOING
  else
    state=TODO
  fi
  printf '%-6s %-4s %s\n' "$state" "$num" "$slug"
done

if [ "$claimed_count" -gt 0 ]; then
  echo "sprint-status: $claimed_count docs still carry the legacy .CLAIMED suffix; state is derived now — rename them to NN-slug.md" >&2
fi
