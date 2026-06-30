#!/usr/bin/env bash
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
WRAP="$HERE/../run-codex.sh"
PASS=0; FAIL=0
ok() { PASS=$((PASS+1)); printf 'ok   - %s\n' "$1"; }
no() { FAIL=$((FAIL+1)); printf 'FAIL - %s\n' "$1"; }
has() { case "$2" in *"$3"*) ok "$1";; *) no "$1 (missing: $3)";; esac; }

export PATH="$HERE/fake-codex:$PATH"
chmod +x "$HERE/fake-codex/codex" "$WRAP" 2>/dev/null || true

# hermetic codex base + overlay (never touch real ~/.codex)
export CODEX_BASE="$(mktemp -d)"; : > "$CODEX_BASE/auth.json"; : > "$CODEX_BASE/config.toml"
export CODEX_HOME_OVERLAY="$(mktemp -d)/ov"

REPO="$(mktemp -d)"; ( cd "$REPO" && git init -q && git commit -q --allow-empty -m init )
OUT="$(mktemp -d)"; PROMPT="$(mktemp)"; printf 'goal: test\n' > "$PROMPT"
export FAKE_CODEX_LOG="$(mktemp)"

"$WRAP" run --repo "$REPO" --prompt-file "$PROMPT" --out-dir "$OUT" --effort high >/dev/null 2>"$OUT/err"
rc=$?
[ "$rc" = 0 ] && ok "run exits 0" || no "run exits 0 (rc=$rc, $(cat "$OUT/err"))"

# overlay built correctly
LINK="$(readlink "$CODEX_HOME_OVERLAY/AGENTS.md" 2>/dev/null)"
[ "$(basename "$LINK" 2>/dev/null)" = "CHARTER.md" ] && ok "overlay AGENTS.md -> CHARTER.md" || no "overlay AGENTS.md link wrong ($LINK)"
[ "$(readlink "$CODEX_HOME_OVERLAY/auth.json" 2>/dev/null)" = "$CODEX_BASE/auth.json" ] && ok "overlay auth.json inherited" || no "overlay auth.json link wrong"
[ "$(readlink "$CODEX_HOME_OVERLAY/config.toml" 2>/dev/null)" = "$CODEX_BASE/config.toml" ] && ok "overlay config.toml inherited" || no "overlay config.toml link wrong"

# captured + relayed
[ "$(cat "$OUT/session_id.txt" 2>/dev/null)" = "11111111-2222-4333-8444-555555555555" ] && ok "thread_id extracted" || no "thread_id extracted (got: $(cat "$OUT/session_id.txt" 2>/dev/null))"
has "final message relayed" "$(cat "$OUT/last.txt" 2>/dev/null)" "CODEX FINAL MESSAGE (fake)"

# posture in argv + CODEX_HOME
LOG="$(cat "$FAKE_CODEX_LOG")"
has "runs under overlay CODEX_HOME" "$LOG" "CODEX_HOME=$CODEX_HOME_OVERLAY"
has "passes --json"                 "$LOG" "--json"
has "passes -C repo"                "$LOG" "$REPO"
has "passes --sandbox ws-write"     "$LOG" "workspace-write"
has "approval_policy=never"         "$LOG" "approval_policy=never"
has "network_access=true"           "$LOG" "sandbox_workspace_write.network_access=true"
has "reasoning effort"              "$LOG" "model_reasoning_effort=high"
case "$LOG" in *$'\n'"-m"$'\n'*) no "must not pin model (-m present)";; *) ok "model not pinned";; esac

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" = 0 ]
