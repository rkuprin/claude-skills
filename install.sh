#!/usr/bin/env bash
# install.sh — symlink every skill in this repo into your Claude skills dir.
# A "skill" is any top-level directory that contains a SKILL.md. Idempotent:
# safe to re-run after adding a new skill or pulling updates.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST="${CLAUDE_SKILLS_DIR:-$HOME/.claude/skills}"
mkdir -p "$DEST"

count=0
for skill in "$ROOT"/*/; do
  [ -f "$skill/SKILL.md" ] || continue          # only dirs that are actually skills
  name="$(basename "$skill")"
  ln -snf "${skill%/}" "$DEST/$name"
  echo "linked  $name  ->  $DEST/$name"
  count=$((count + 1))
done

if [ "$count" -eq 0 ]; then
  echo "no skills found — a skill is a top-level directory containing a SKILL.md" >&2
  exit 1
fi
echo "installed $count skill(s) into $DEST"
echo "note: some skills need extra setup (CLI tools, auth) — see each skill's README.md"
