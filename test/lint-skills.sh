#!/usr/bin/env bash
# lint-skills.sh — invariants the sprint skills must hold. Prose is the product; lint it.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ORCH="$HERE/../sprint-orchestrator/SKILL.md"
ORCH_YAML="$HERE/../sprint-orchestrator/agents/openai.yaml"
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
has   "orchestrator: kickoff line addresses planner, not executor" "executor does not run this" "$ORCH"
# The two agents guard implicit invocation with different keys. Both must be set, or the skill
# silently becomes model-invocable on one side. Claude: SKILL.md. Codex: agents/openai.yaml.
has   "orchestrator: claude blocks implicit invocation" "disable-model-invocation: true" "$ORCH"
has   "orchestrator: codex blocks implicit invocation"  "allow_implicit_invocation: false" "$ORCH_YAML"
# DONE needs BOTH trailers. Story numbers restart each sprint, so `Story: NN` alone collides.
done_row=$(grep -F '| `DONE` |' "$ORCH")
case "$done_row" in
  *Sprint*) ok "orchestrator: DONE row requires the Sprint trailer too" ;;
  *) no "orchestrator: DONE row requires the Sprint trailer too (found: $done_row)" ;;
esac

# --- codex-execution-handoff ---
HAND="$HERE/../codex-execution-handoff/SKILL.md"
bad=$(grep -nF 'git checkout main' "$HAND" | grep -viE 'never|do not|don.t|instead of' || true)
[ -z "$bad" ] && ok "handoff: git checkout main only ever appears negated" \
               || no "handoff: git checkout main appears as an instruction ($bad)"
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
ctx3=$(grep -F "unable to keep prod green" "$HAND")
case "$ctx3" in
  *"approved driver"*) ok "handoff: goal explainer names all three interrupts" ;;
  *) no "handoff: goal explainer names all three interrupts (missing third condition next to explainer bullet)" ;;
esac
has   "handoff: stop-at-pr variant"          "stop-at-pr"        "$HAND"
# The deploy gate must check both trailers, not just Story:.
gate=$(grep -F 'Gate EVERY deploy on:' "$HAND")
case "$gate" in
  *"Story: NN"*) ok "handoff: deploy gate names the Story trailer" ;;
  *) no "handoff: deploy gate names the Story trailer" ;;
esac
grep -A1 -F 'Gate EVERY deploy on:' "$HAND" | grep -qF 'Sprint:' \
  && ok "handoff: deploy gate names the Sprint trailer too" \
  || no "handoff: deploy gate names the Sprint trailer too"
# The GOOD /goal example must name all three interrupts, like the template does.
grep -F 'GOOD (late checkpoint)' -A5 "$HAND" | grep -qF 'approved driver' \
  && ok "handoff: goal example names all three interrupts" \
  || no "handoff: goal example names all three interrupts"
has   "handoff: executor never invokes it"   "never invoked by the executing" "$HAND"

# --- agent-handoff (SKILL.md) ---
AH="$HERE/../agent-handoff/SKILL.md"
# Frontmatter sanity without a YAML parser: name matches the directory, and the description is a
# quoted scalar — the retired codex-execution-handoff description was unquoted, contained
# "Triggers:", and silently failed YAML parsing. Grep can prevent that class.
grep -q '^name: agent-handoff$' "$AH" 2>/dev/null && ok "handoff: name matches directory" || no "handoff: name matches directory"
grep -q '^description: "' "$AH" 2>/dev/null && ok "handoff: description is a quoted scalar" || no "handoff: description is a quoted scalar"
hasnt "handoff: model-invocable (no manual-only guard)" "disable-model-invocation" "$AH"
has   "handoff: /goal ends every prompt"     "/goal"              "$AH"
has   "handoff: names Codex.app"             "Codex.app"          "$AH"
has   "handoff: report-only default"         "Report-only by default" "$AH"
has   "handoff: mutation grant"              "mutation grant"     "$AH"
has   "handoff: workspace identity (SHA)"    "HEAD SHA"           "$AH"
has   "handoff: task files in ~/.handoffs"   "~/.handoffs"        "$AH"
has   "handoff: EXECUTION MODE inline"       "EXECUTION MODE"     "$AH"
has   "handoff: stop-at-pr rendered loud"    "STOP AT PR — DO NOT MERGE OR DEPLOY" "$AH"
has   "handoff: codex contract path"         "~/.codex/skills/agent-handoff/EXECUTION.md" "$AH"
has   "handoff: claude contract path"        "~/.claude/skills/agent-handoff/EXECUTION.md" "$AH"
has   "handoff: task mode excludes sprint stories" "numbered sprint story" "$AH"
has   "handoff: capability outranks affinity" "Capability outranks affinity" "$AH"
has   "handoff: hard rules name the story trailer"  "Story: {NN}"   "$AH"
has   "handoff: hard rules name the sprint trailer" "Sprint: {SPRINT}" "$AH"
bad=$(grep -nF 'git checkout main' "$AH" 2>/dev/null | grep -viE 'never|do not|don.t|instead of' || true)
[ -z "$bad" ] && ok "handoff: git checkout main only ever negated" || no "handoff: git checkout main appears as an instruction ($bad)"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
