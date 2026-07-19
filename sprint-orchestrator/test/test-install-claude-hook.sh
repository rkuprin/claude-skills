#!/usr/bin/env bash
# Hermetic tests for install-claude-hook.sh — fresh-machine wiring, idempotency,
# stale-path repointing, and preservation of a co-installed Stop hook. No trust
# dance (Claude settings-json hooks activate on write), so no codex stub is needed.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SUT="$HERE/../install-claude-hook.sh"
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
