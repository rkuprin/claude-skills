#!/usr/bin/env bash
# lint-skills.sh — invariants the sprint skills must hold. Prose is the product; lint it.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ORCH="$HERE/../sprint-orchestrator/SKILL.md"
PASS=0; FAIL=0
ok() { PASS=$((PASS+1)); printf 'ok   - %s\n' "$1"; }
no() { FAIL=$((FAIL+1)); printf 'FAIL - %s\n' "$1"; }
has()   { grep -qF -- "$2" "$3" && ok "$1" || no "$1 (missing: $2)"; }
hasnt() { grep -qF -- "$2" "$3" && no "$1 (found: $2)" || ok "$1"; }

# --- sprint-orchestrator ---
hasnt "orchestrator: no CLAIMED state"      ".CLAIMED.md"        "$ORCH"
hasnt "orchestrator: no done/ archive"      "done/"              "$ORCH"
hasnt "orchestrator: no unconditional 'do not merge'" "do not merge" "$ORCH"
hasnt "orchestrator: no checkout of trunk"  "git checkout main"  "$ORCH"
hasnt "orchestrator: no HANDOFF.md"         "HANDOFF.md"         "$ORCH"
hasnt "orchestrator: no dead mode field"    "mode: shaped"       "$ORCH"
hasnt "orchestrator: no narrow story glob"  "[0-9][0-9]-*.md"    "$ORCH"
has   "orchestrator: names sprint-status"   "sprint-status.sh"   "$ORCH"
has   "orchestrator: conversation field"    "conversation:"      "$ORCH"
has   "orchestrator: execution field"       "execution:"         "$ORCH"
has   "orchestrator: frontend field"        "frontend:"          "$ORCH"
has   "orchestrator: surfaces field"        "surfaces:"          "$ORCH"
has   "orchestrator: browser verification"  "## Browser Verification" "$ORCH"
has   "orchestrator: owns_hunk promoted"    "owns_hunk:"         "$ORCH"
has   "orchestrator: wave promoted"         "wave:"              "$ORCH"
hasnt "orchestrator: no filesystem ledger claim" "filesystem remains the ledger" "$ORCH"
hasnt "orchestrator: no filesystem-backed desc" "filesystem-backed" "$ORCH"

# --- codex-execution-handoff ---
HAND="$HERE/../codex-execution-handoff/SKILL.md"
hasnt "handoff: never checks out trunk"      "git checkout main" "$HAND"
hasnt "handoff: no per-sprint HANDOFF.md"    "HANDOFF.md"        "$HAND"
hasnt "handoff: no CLAIMED rename"           ".CLAIMED.md"       "$HAND"
hasnt "handoff: no done/ archive"            "done/"             "$HAND"
hasnt "handoff: does not tell a model to invoke the manual planner" "invoke \`sprint-orchestrator\`" "$HAND"
has   "handoff: story trailer"               "Story: NN"         "$HAND"
has   "handoff: sprint trailer"              "Sprint:"           "$HAND"
has   "handoff: worktree-safe branching"     "git switch -c"     "$HAND"
has   "handoff: refuses a taken story"       "already exists"    "$HAND"
has   "handoff: approved drivers"            "approved driver"   "$HAND"
has   "handoff: bans DOM substitution"       "DOM"               "$HAND"
has   "handoff: evidence outside the repo"   ".sprint-evidence"  "$HAND"
has   "handoff: names Codex.app"             "Codex.app"         "$HAND"
has   "handoff: third interrupt condition"   "approved driver can drive" "$HAND"
has   "handoff: stop-at-pr variant"          "stop-at-pr"        "$HAND"
has   "handoff: executor never invokes it"   "never invoked by the executing" "$HAND"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
