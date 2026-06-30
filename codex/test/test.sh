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

# --- guard: non-git repo ---
NOGIT="$(mktemp -d)"
"$WRAP" run --repo "$NOGIT" --prompt-file "$PROMPT" --out-dir "$(mktemp -d)" >/dev/null 2>"$OUT/err2"; rc=$?
[ "$rc" != 0 ] && ok "non-git repo rejected" || no "non-git repo rejected (rc=0)"
has "non-git message actionable" "$(cat "$OUT/err2")" "not a git repo"

# --- guard: missing prompt file ---
"$WRAP" run --repo "$REPO" --prompt-file /no/such/file --out-dir "$(mktemp -d)" >/dev/null 2>"$OUT/err3"; rc=$?
[ "$rc" != 0 ] && ok "missing prompt rejected" || no "missing prompt rejected (rc=0)"

# --- guard: codex non-zero exit surfaces ---
FAILDIR="$(mktemp -d)"; printf '%s\n' '#!/usr/bin/env bash' 'exit 7' > "$FAILDIR/codex"; chmod +x "$FAILDIR/codex"
PATH="$FAILDIR:$PATH" "$WRAP" run --repo "$REPO" --prompt-file "$PROMPT" --out-dir "$(mktemp -d)" >/dev/null 2>"$OUT/err4"; rc=$?
[ "$rc" != 0 ] && ok "codex failure surfaced" || no "codex failure surfaced (rc=0)"

# --- resume path ---
: > "$FAKE_CODEX_LOG"
OUT2="$(mktemp -d)"; REPLY="$(mktemp)"; printf 'rebuttal: consider X\n' > "$REPLY"
SID="11111111-2222-4333-8444-555555555555"
"$WRAP" resume --session-id "$SID" --repo "$REPO" --prompt-file "$REPLY" --out-dir "$OUT2" >/dev/null 2>"$OUT2/err"; rc=$?
[ "$rc" = 0 ] && ok "resume exits 0" || no "resume exits 0 (rc=$rc, $(cat "$OUT2/err"))"
RLOG="$(cat "$FAKE_CODEX_LOG")"
has "resume under overlay CODEX_HOME" "$RLOG" "CODEX_HOME=$CODEX_HOME_OVERLAY"
has "resume subcommand used"          "$RLOG" "resume"
has "resume passes session id"        "$RLOG" "$SID"
has "resume sandbox via -c"           "$RLOG" "sandbox_mode=workspace-write"
has "resume keeps approval off"       "$RLOG" "approval_policy=never"
has "resume relays new message"       "$(cat "$OUT2/last.txt" 2>/dev/null)" "CODEX FINAL MESSAGE (fake)"
case "$RLOG" in *$'\n'"-C"$'\n'*) no "resume must not pass -C";; *) ok "resume omits -C";; esac
case "$RLOG" in *$'\n'"--sandbox"$'\n'*) no "resume must not pass --sandbox";; *) ok "resume omits --sandbox flag";; esac

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" = 0 ]
