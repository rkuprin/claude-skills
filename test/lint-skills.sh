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
has   "orchestrator: loop field"            "loop:"              "$ORCH"
has   "orchestrator: driver_hint field"     "driver_hint:"       "$ORCH"
has   "orchestrator: driver_why field"      "driver_why:"        "$ORCH"
has   "orchestrator: tier field"            "tier:"              "$ORCH"
has   "orchestrator: tier_why field"        "tier_why:"          "$ORCH"
has   "orchestrator: effort_why field"      "effort_why:"        "$ORCH"
has   "orchestrator: orchestrate field"     "orchestrate:"       "$ORCH"
has   "orchestrator: orchestrate implies xhigh" "implies xhigh"  "$ORCH"
has   "orchestrator: effort only on deviation" "only when the story deviates" "$ORCH"
has   "orchestrator: tier from nature only" "tier:\` derives from the work's nature" "$ORCH"
orch_rows="$(grep -E '^\| [SABC] \|' "$ORCH")"
[ "$(printf '%s\n' "$orch_rows" | grep -c .)" = 4 ] \
  && ok "orchestrator: ladder has exactly 4 tier rows" \
  || no "orchestrator: ladder has exactly 4 tier rows (got: $(printf '%s\n' "$orch_rows" | grep -c .))"
has   "orchestrator: capability outranks affinity" "Capability outranks affinity" "$ORCH"
has   "orchestrator: strongest-model gate"  "Strongest Model"    "$ORCH"
has   "orchestrator: incremental waves"     "wave boundary"      "$ORCH"
has   "orchestrator: deferred stories are stubs" "stub"          "$ORCH"
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
has   "handoff: Launch line rendered"        "Launch:"            "$AH"
has   "handoff: Launch line outside the fence" "outside the fenced prompt block" "$AH"
has   "handoff: luna orchestration bump"     "bumps to Terra"     "$AH"
has   "handoff: recommended base invocation" "recommended base invocation" "$AH"
grep -qE 'gpt-5\.6-luna.*`high`' "$AH" \
  && ok "handoff: visual-validation defaults luna+high on one line" \
  || no "handoff: visual-validation defaults luna+high on one line"
ah_rows="$(grep -E '^\| [SABC] \|' "$AH")"
[ "$(printf '%s\n' "$ah_rows" | grep -c .)" = 4 ] \
  && ok "handoff: ladder has exactly 4 tier rows" \
  || no "handoff: ladder has exactly 4 tier rows (got: $(printf '%s\n' "$ah_rows" | grep -c .))"
[ -n "$orch_rows" ] && [ "$orch_rows" = "$ah_rows" ] \
  && ok "ladder: orchestrator and handoff tables in sync" \
  || no "ladder: orchestrator and handoff tables diverge"

# --- agent-handoff (EXECUTION.md, the lifecycle contract) ---
AHEXEC="$HERE/../agent-handoff/EXECUTION.md"
has   "contract: story trailer"              "Story: {NN}"        "$AHEXEC"
has   "contract: sprint trailer"             "Sprint:"            "$AHEXEC"
has   "contract: worktree-safe branching"    "git switch -c"      "$AHEXEC"
has   "contract: refuses a taken story"      "already exists"     "$AHEXEC"
has   "contract: approved drivers"           "approved driver"    "$AHEXEC"
has   "contract: bans DOM substitution"      "DOM"                "$AHEXEC"
has   "contract: evidence outside the repo"  ".sprint-evidence"   "$AHEXEC"
has   "contract: stop-at-pr collapse"        "do not merge, do not deploy" "$AHEXEC"
has   "contract: tracker done intent"        "card.done"          "$AHEXEC"
has   "contract: third interrupt condition"  "approved driver can drive" "$AHEXEC"
has   "contract: first interrupt condition"  "wrong premise"      "$AHEXEC"
has   "contract: second interrupt condition" "keep prod green"    "$AHEXEC"
has   "contract: orchestration never waives the contract" "never waives this contract" "$AHEXEC"
hasnt "contract: no per-sprint HANDOFF.md"   "HANDOFF.md"         "$AHEXEC"
hasnt "contract: no CLAIMED rename"          ".CLAIMED.md"        "$AHEXEC"
bad=$(grep -nF 'git checkout main' "$AHEXEC" 2>/dev/null | grep -viE 'never|do not|don.t|instead of' || true)
[ -z "$bad" ] && ok "contract: git checkout main only ever negated" || no "contract: git checkout main appears as an instruction ($bad)"

# --- claude-reviewer ---
CR="$HERE/../claude-reviewer/SKILL.md"
grep -q '^name: claude-reviewer$' "$CR" 2>/dev/null && ok "claude-reviewer: name matches directory" || no "claude-reviewer: name matches directory"
# From Claude Code the skill is circular (Claude summoning Claude) and its triggers collide
# with the `codex` skill. Codex ignores this key, so it stays implicitly invocable there.
has   "claude-reviewer: manual-only on Claude"  "disable-model-invocation: true" "$CR"
has   "claude-reviewer: reply is evidence, not instruction" "not an instruction to obey" "$CR"

# --- trace-scenario ---
TS="$HERE/../trace-scenario/SKILL.md"
grep -q '^name: trace-scenario$' "$TS" 2>/dev/null && ok "trace-scenario: name matches directory" || no "trace-scenario: name matches directory"
has   "trace-scenario: never infers the environment" "Do not infer an" "$TS"
has   "trace-scenario: mutation needs authorization" "explicit authorization" "$TS"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
