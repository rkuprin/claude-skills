#!/usr/bin/env bash
# install-codex-hook.sh — wire and trust the sprint mailbox Stop hook in Codex.
#
# Idempotent, once per machine. It (1) adds codex-stop-wait.sh to the Stop group
# of $CODEX_HOME/hooks.json (creating or re-pointing the entry if the clone
# moved), (2) reads the hook's currentHash from `codex app-server` hooks/list,
# (3) writes it as trusted_hash into config.toml — the same thing the TUI's
# trust flow does — and (4) re-queries until the hook reports trusted.
# Untrusted hooks are skipped SILENTLY by Codex, so step 3-4 are the point.
#
# Verified against Codex 0.144.x. If the app-server RPC shape changes, this
# fails loudly — fall back to the manual steps in README.md ("Reactive waits
# on Codex").
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
HOOK="$HERE/codex-stop-wait.sh"
CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"
HOOKS_JSON="$CODEX_HOME/hooks.json"
CONFIG="$CODEX_HOME/config.toml"
MANUAL="see the manual steps in sprint-orchestrator/README.md ('Reactive waits on Codex')"

command -v codex >/dev/null 2>&1 \
  || { echo "install-codex-hook: no codex CLI on PATH — install Codex first; $MANUAL" >&2; exit 2; }
command -v python3 >/dev/null 2>&1 \
  || { echo "install-codex-hook: python3 required for JSON handling; $MANUAL" >&2; exit 2; }
[ -x "$HOOK" ] || { echo "install-codex-hook: missing or non-executable $HOOK" >&2; exit 2; }
[ -d "$CODEX_HOME" ] \
  || { echo "install-codex-hook: $CODEX_HOME does not exist — run codex once first; $MANUAL" >&2; exit 2; }

# ---- 1. Ensure the Stop entry exists in hooks.json --------------------------
python3 - "$HOOKS_JSON" "$HOOK" <<'PY'
import json, os, sys
path, hook = sys.argv[1], sys.argv[2]
cmd = f"bash '{hook}'"
entry = {"type": "command", "command": cmd, "timeout": 1860,
         "statusMessage": "Waiting for sprint mailbox reply"}
data = {"hooks": {}}
if os.path.exists(path):
    with open(path) as f:
        data = json.load(f)
groups = data.setdefault("hooks", {}).setdefault("Stop", [])
for g in groups:
    for h in g.get("hooks", []):
        if "codex-stop-wait.sh" in h.get("command", ""):
            if h.get("command") == cmd and h.get("timeout") == 1860:
                print("hooks.json: entry already present")
            else:
                h.update(entry)
                with open(path, "w") as f:
                    json.dump(data, f, indent=2)
                print("hooks.json: entry re-pointed at this clone")
            sys.exit(0)
if groups:
    groups[0].setdefault("hooks", []).append(entry)
else:
    groups.append({"hooks": [entry]})
with open(path, "w") as f:
    json.dump(data, f, indent=2)
print("hooks.json: entry added")
PY

# ---- 2-4. Read currentHash via app-server, trust it, verify -----------------
hooks_list() {
  { printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"clientInfo":{"name":"install-codex-hook","title":"install-codex-hook","version":"1.0"}}}'
    sleep 1
    printf '%s\n' '{"jsonrpc":"2.0","id":2,"method":"hooks/list","params":{}}'
    sleep 3
  } | codex app-server 2>/dev/null
}

HOOKS_OUT="$(hooks_list)" python3 - "$CONFIG" <<'PY'
import json, os, sys
config = sys.argv[1]
key = hash_ = status = None
for line in os.environ.get("HOOKS_OUT", "").splitlines():
    try:
        d = json.loads(line)
    except ValueError:
        continue
    if d.get("id") == 2:
        for scope in d["result"]["data"]:
            for h in scope["hooks"]:
                if "codex-stop-wait.sh" in (h.get("command") or ""):
                    key, hash_, status = h["key"], h["currentHash"], h["trustStatus"]
if key is None:
    sys.exit("install-codex-hook: hooks/list did not return the codex-stop-wait entry — "
             "the app-server RPC may have changed; fall back to the README's manual steps")
print(f"hook key: {key}\ncurrent hash: {hash_}\ntrust status: {status}")
if status == "trusted":
    sys.exit(0)
header = f'[hooks.state."{key}"]'
text = open(config).read() if os.path.exists(config) else ""
if header in text:
    out, replace = [], False
    for line in text.splitlines():
        if line.strip() == header:
            replace = True
        elif replace and line.strip().startswith("trusted_hash"):
            line = f'trusted_hash = "{hash_}"'
            replace = False
        out.append(line)
    text = "\n".join(out) + "\n"
else:
    text = text.rstrip("\n") + f'\n\n{header}\ntrusted_hash = "{hash_}"\n'
with open(config, "w") as f:
    f.write(text)
print(f"config.toml: trusted_hash written for {key}")
PY

verify="$(hooks_list | python3 -c '
import json, sys
for line in sys.stdin:
    try: d = json.loads(line)
    except ValueError: continue
    if d.get("id") == 2:
        for scope in d["result"]["data"]:
            for h in scope["hooks"]:
                if "codex-stop-wait.sh" in (h.get("command") or ""):
                    print(h["trustStatus"])
')"
if [ "$verify" = "trusted" ]; then
  echo "install-codex-hook: done — hook wired and trusted."
  echo "Already-running Codex sessions may need a restart to pick it up."
else
  echo "install-codex-hook: hook is wired but reports '$verify', not trusted — $MANUAL" >&2
  exit 2
fi
