#!/usr/bin/env bash
# Hermetic tests for install-codex-hook.sh — fresh-machine wiring and idempotency.
# `codex` is stubbed: its canned hooks/list derives trustStatus from whether
# config.toml already carries the hash, mirroring the real trust mechanics.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SUT="$HERE/../install-codex-hook.sh"
PASS=0; FAIL=0
ok() { PASS=$((PASS+1)); printf 'ok   - %s\n' "$1"; }
no() { FAIL=$((FAIL+1)); printf 'FAIL - %s\n' "$1"; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export CODEX_HOME="$TMP/codexhome"
mkdir -p "$CODEX_HOME" "$TMP/bin"
printf 'model = "stub"\n' > "$CODEX_HOME/config.toml"

cat > "$TMP/bin/codex" <<'STUB'
#!/usr/bin/env bash
[ "${1:-}" = "app-server" ] || exit 2
cat > /dev/null
status=untrusted
grep -q 'sha256:feedface' "$CODEX_HOME/config.toml" 2>/dev/null && status=trusted
printf '{"id":1,"result":{}}\n'
printf '{"id":2,"result":{"data":[{"cwd":"/x","hooks":[{"key":"%s:stop:0:0","command":"bash '\''/x/codex-stop-wait.sh'\''","currentHash":"sha256:feedface","trustStatus":"%s"}]}]}}\n' \
  "$CODEX_HOME/hooks.json" "$status"
STUB
chmod +x "$TMP/bin/codex"
export PATH="$TMP/bin:$PATH"

# ---- fresh machine: no hooks.json, nothing trusted ----
out="$("$SUT" 2>&1)"; rc=$?
[ "$rc" = "0" ] && ok "fresh install exits 0" || { no "fresh install exits 0 (rc=$rc)"; printf '%s\n' "$out"; }
grep -q "codex-stop-wait.sh" "$CODEX_HOME/hooks.json" 2>/dev/null \
  && ok "hooks.json created with the hook entry" || no "hooks.json created with the hook entry"
grep -q '"timeout": 1860' "$CODEX_HOME/hooks.json" 2>/dev/null \
  && ok "entry carries the 1860s timeout" || no "entry carries the 1860s timeout"
grep -q 'trusted_hash = "sha256:feedface"' "$CODEX_HOME/config.toml" \
  && ok "trusted_hash written to config.toml" || no "trusted_hash written to config.toml"
case "$out" in *"done — hook wired and trusted"*) ok "reports wired and trusted" ;; *) no "reports wired and trusted (got: $out)" ;; esac

# ---- second run: idempotent, no duplicate trust entries ----
out="$("$SUT" 2>&1)"; rc=$?
[ "$rc" = "0" ] && ok "second run exits 0" || no "second run exits 0 (rc=$rc)"
case "$out" in *"entry already present"*) ok "second run leaves hooks.json alone" ;; *) no "second run leaves hooks.json alone (got: $out)" ;; esac
n="$(grep -c 'trusted_hash = "sha256:feedface"' "$CODEX_HOME/config.toml")"
[ "$n" = "1" ] && ok "trusted_hash written exactly once" || no "trusted_hash written exactly once (got: $n)"

# ---- moved clone: existing entry with a stale path gets re-pointed ----
python3 - "$CODEX_HOME/hooks.json" <<'PY'
import json, sys
p = sys.argv[1]
d = json.load(open(p))
d["hooks"]["Stop"][0]["hooks"][0]["command"] = "bash '/old/clone/sprint-orchestrator/codex-stop-wait.sh'"
json.dump(d, open(p, "w"), indent=2)
PY
out="$("$SUT" 2>&1)"
case "$out" in *"re-pointed"*) ok "stale path re-pointed at this clone" ;; *) no "stale path re-pointed at this clone (got: $out)" ;; esac
grep -q "$HERE/../codex-stop-wait.sh\|claude-skills/sprint-orchestrator/codex-stop-wait.sh" "$CODEX_HOME/hooks.json" \
  && ok "re-pointed command names this clone" || no "re-pointed command names this clone"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
