#!/usr/bin/env bash
# run-codex.sh — invoke Codex headless as an independent second perspective.
# The reviewer disposition lives in CHARTER.md, loaded by Codex as the overlay's
# global AGENTS.md (CODEX_HOME); this wrapper carries posture + transport only.
set -euo pipefail

die() { printf 'run-codex: %s\n' "$*" >&2; exit 1; }
usage() {
  cat >&2 <<'EOF'
usage:
  run-codex.sh run    --repo DIR --prompt-file FILE --out-dir DIR [--effort LEVEL]
  run-codex.sh resume --session-id ID --repo DIR --prompt-file FILE --out-dir DIR [--effort LEVEL]
EOF
  exit 2
}

resolve_skill_root() {   # follow the ~/.claude/skills/codex symlink to the real dir
  local src="${BASH_SOURCE[0]}" dir
  while [ -L "$src" ]; do
    dir="$(cd -P "$(dirname "$src")" && pwd)"
    src="$(readlink "$src")"
    case "$src" in /*) ;; *) src="$dir/$src";; esac
  done
  cd -P "$(dirname "$src")" && pwd
}

extract_session_id() {   # $1 = events.jsonl -> prints thread/session UUID, or returns 1
  local events="$1" id filt
  local re='^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
  for filt in \
    'select(.type=="thread.started")  | (.thread_id  // .session_id // .id // empty)' \
    'select(.type=="session.created") | (.session_id // .session.id // .id // empty)' \
    'select((.type//"")|test("thread|session|configured|started")) | (.thread_id // .session_id // .conversation_id // .id // empty)' \
    '.thread_id // .session_id // .conversation_id // empty'; do
    id=$(jq -r "$filt" "$events" 2>/dev/null | grep -Eim1 "$re" || true)
    [ -n "$id" ] && { printf '%s\n' "$id"; return 0; }
  done
  return 1
}

SKILL_ROOT="$(resolve_skill_root)"
CODEX_BASE="${CODEX_BASE:-$HOME/.codex}"
OVERLAY="${CODEX_HOME_OVERLAY:-$SKILL_ROOT/codex-home}"
CHARTER="$SKILL_ROOT/CHARTER.md"

ensure_overlay() {
  [ -f "$CHARTER" ] || die "charter not found: $CHARTER (run Task 1 relocation)"
  mkdir -p "$OVERLAY"
  ln -snf "$CHARTER"                 "$OVERLAY/AGENTS.md"
  ln -snf "$CODEX_BASE/auth.json"    "$OVERLAY/auth.json"
  ln -snf "$CODEX_BASE/config.toml"  "$OVERLAY/config.toml"
}

cmd="${1:-}"; [ -n "$cmd" ] || usage; shift
repo="" prompt_file="" out_dir="" effort="high" session_id=""
while [ $# -gt 0 ]; do
  case "$1" in
    --repo)        repo="${2:-}"; shift 2;;
    --prompt-file) prompt_file="${2:-}"; shift 2;;
    --out-dir)     out_dir="${2:-}"; shift 2;;
    --effort)      effort="${2:-}"; shift 2;;
    --session-id)  session_id="${2:-}"; shift 2;;
    *) die "unknown arg: $1";;
  esac
done

[ -n "$repo" ]        || die "missing --repo"
[ -n "$prompt_file" ] || die "missing --prompt-file"
[ -n "$out_dir" ]     || die "missing --out-dir"
[ -f "$prompt_file" ] || die "prompt file not found: $prompt_file"
git -C "$repo" rev-parse --is-inside-work-tree >/dev/null 2>&1 \
  || die "not a git repo: $repo — Codex needs one. cd into the project repo or pass its root with --repo."

ensure_overlay
mkdir -p "$out_dir"
events="$out_dir/events.jsonl"; last="$out_dir/last.txt"; sid_file="$out_dir/session_id.txt"
overrides=( -c "approval_policy=never"
            -c "sandbox_workspace_write.network_access=true"
            -c "model_reasoning_effort=$effort" )

case "$cmd" in
  run)
    CODEX_HOME="$OVERLAY" codex exec --json --output-last-message "$last" \
      -C "$repo" --sandbox workspace-write \
      "${overrides[@]}" - < "$prompt_file" > "$events" \
      || die "codex exec failed — see $events"
    sid="$(extract_session_id "$events")" || die "could not extract thread_id from $events"
    printf '%s\n' "$sid" > "$sid_file"
    ;;
  resume)
    [ -n "$session_id" ] || die "missing --session-id"
    # resume rejects --sandbox and -C: set sandbox via -c, cd into the repo.
    ( cd "$repo" && CODEX_HOME="$OVERLAY" codex exec resume "$session_id" --json \
        --output-last-message "$last" \
        -c "sandbox_mode=workspace-write" "${overrides[@]}" - < "$prompt_file" ) > "$events" \
        || die "codex exec resume failed — see $events"
    printf '%s\n' "$session_id" > "$sid_file"
    ;;
  *) usage;;
esac

[ -s "$last" ] || die "codex produced no final message — see $events"
printf 'ok session_id=%s last=%s\n' "$(cat "$sid_file")" "$last"
