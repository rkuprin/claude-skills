#!/usr/bin/env bash
# install-claude-hook.sh — wire the sprint mailbox Stop hook into Claude Code.
#
# Idempotent, once per machine. Appends claude-stop-wait.sh as its OWN Stop group
# in ${CLAUDE_CONFIG_DIR:-~/.claude}/settings.json, PRESERVING any co-installed
# Stop hooks (an iTerm-status Stop hook is present on this machine and must
# survive) — existing groups are never mutated.
#
# No trust dance (unlike install-codex-hook.sh): Claude settings-json hooks
# activate on write — user-settings edits auto-reload; a session restart is the
# fallback. timeout 10860 = the 3h idle-wait budget (10800) plus 60s slack.
#
# Honest limit: a settings.json reference is not proof the hook RUNS — managed
# policy or `disableAllHooks` can suppress it. Those are reported, not silently
# worked around.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
HOOK="$HERE/claude-stop-wait.sh"
CFG_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
SETTINGS="$CFG_DIR/settings.json"
MANUAL="see the manual steps in sprint-orchestrator/README.md ('Reactive waits on Claude')"

command -v python3 >/dev/null 2>&1 \
  || { echo "install-claude-hook: python3 required for JSON handling; $MANUAL" >&2; exit 2; }
[ -x "$HOOK" ] || { echo "install-claude-hook: missing or non-executable $HOOK" >&2; exit 2; }
[ -d "$CFG_DIR" ] \
  || { echo "install-claude-hook: $CFG_DIR does not exist — run claude once first; $MANUAL" >&2; exit 2; }

python3 - "$SETTINGS" "$HOOK" <<'PY'
import json, os, sys
path, hook = sys.argv[1], sys.argv[2]
cmd = f"bash '{hook}'"
entry = {"type": "command", "command": cmd, "timeout": 10860,
         "statusMessage": "Waiting for sprint mailbox reply"}
data = {}
if os.path.exists(path):
    with open(path) as f:
        data = json.load(f)
groups = data.setdefault("hooks", {}).setdefault("Stop", [])
for g in groups:
    for h in g.get("hooks", []):
        if "claude-stop-wait.sh" in h.get("command", ""):
            if h.get("command") == cmd and h.get("timeout") == 10860:
                print("settings.json: entry already present")
            else:
                h.update(entry)
                with open(path, "w") as f:
                    json.dump(data, f, indent=2)
                print("settings.json: entry re-pointed at this clone")
            sys.exit(0)
groups.append({"matcher": "", "hooks": [entry]})   # own group — never mutate a co-installed one
with open(path, "w") as f:
    json.dump(data, f, indent=2)
print("settings.json: entry added")
PY

echo "install-claude-hook: done — hook wired in $SETTINGS."
echo "Running Claude sessions pick up settings-json hook edits automatically; a restart is the fallback."
echo "If hooks are disabled (disableAllHooks / managed policy), this reference will not fire until that is lifted."
