#!/usr/bin/env bash
# test-wave-handoffs.sh — fixture stories in a temp sprint dir; assert rendered Launch lines.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
WH="$HERE/../wave-handoffs.sh"
PASS=0; FAIL=0
ok() { PASS=$((PASS+1)); printf 'ok   - %s\n' "$1"; }
no() { FAIL=$((FAIL+1)); printf 'FAIL - %s\n' "$1"; }
has() { case "$2" in *"$3"*) ok "$1";; *) no "$1 (missing: $3)";; esac; }

SPRINT_NAME="2026-07-10-fixture-sprint"
SPRINT="$(mktemp -d)/$SPRINT_NAME"; mkdir -p "$SPRINT"

story() {  # $1=NN $2=slug, remaining args = extra frontmatter lines (win over defaults via grep -m1)
  local nn="$1" slug="$2"; shift 2
  { printf -- '---\nstory: %s\ntitle: %s\nconversation: "%s · Story %s: Fixture Case Doc"\n' "$nn" "$slug" "$SPRINT_NAME" "$nn"
    local line; for line in "$@"; do printf '%s\n' "$line"; done
    printf 'sprint: %s\nbranch: sprint/%s/%s-%s\nexecution: stop-at-pr\nflow: mechanical\nloop: direct\nwave: 1\n' "$SPRINT_NAME" "$SPRINT_NAME" "$nn" "$slug"
    printf -- '---\n\n## Objective\nFixture objective %s.\n\n## Goal\n\n/goal fixture goal %s\n' "$nn" "$nn"
  } > "$SPRINT/$nn-$slug.md"
}

story 07 tier-b-codex     'driver_hint: codex'  'tier: B              # opus (claude) / gpt-5.6-terra (codex)' 'tier_why: fixture'
story 08 tier-c-deviation 'driver_hint: claude' 'tier: C' 'tier_why: fixture' 'effort: medium' 'effort_why: fixture sweep'
story 09 tier-b-orch      'driver_hint: codex'  'tier: B' 'tier_why: fixture' 'orchestrate: true'
story 10 tier-c-orch-bump 'driver_hint: codex'  'tier: C' 'tier_why: fixture' 'orchestrate: true'
story 11 legacy-no-tier   'driver_hint: claude'
story 12 tier-b-either    'driver_hint: either' 'tier: B' 'tier_why: fixture'
story 13 tier-s-claude    'driver_hint: claude' 'tier: S' 'tier_why: fixture'
story 14 tier-a-codex     'driver_hint: codex'  'tier: A' 'tier_why: fixture'
story 15 tier-s-conflict  'driver_hint: codex'  'tier: S' 'tier_why: fixture'
story 16 tier-q-unknown   'driver_hint: claude' 'tier: Q' 'tier_why: fixture'
story 17 tier-s-either    'driver_hint: either' 'tier: S' 'tier_why: fixture'
story 18 tier-c-orch-effort 'driver_hint: claude' 'tier: C' 'tier_why: fixture' 'orchestrate: true' 'effort: medium' 'effort_why: fixture'
story 19 bare-legacy
story 20 full-loop       'driver_hint: claude' 'tier: B' 'tier_why: fixture' 'loop: full'
story 21 direction-probe 'driver_hint: claude' 'tier: S' 'tier_why: fixture' 'loop: full' 'flow: direction'
story 22 design-heavy    'driver_hint: claude' 'tier: B' 'tier_why: fixture' 'loop: full' 'flow: design-heavy'
story 30 full-only-w3    'wave: 3' 'driver_hint: claude' 'tier: B' 'tier_why: fixture' 'loop: full'

OUTPUT="$("$WH" "$SPRINT" 1 --topology main-session 2>&1)" && ok "wave-handoffs runs" || { no "wave-handoffs runs"; printf '%s\n' "$OUTPUT"; }

has "B/codex resolves terra xhigh"    "$OUTPUT" 'Launch: gpt-5.6-terra · xhigh (tier B)'
has "C/claude deviation renders medium" "$OUTPUT" 'Launch: sonnet · medium (tier C)'
has "orchestrated B/codex is ultra"   "$OUTPUT" 'Launch: gpt-5.6-terra · ultra (tier B)'
has "orchestrated C bumps luna to terra" "$OUTPUT" 'Launch: gpt-5.6-terra · ultra (tier C)'
has "legacy story marks tier unset"   "$OUTPUT" 'tier unset, default B assumed'
has "legacy resolves row B on claude" "$OUTPUT" 'Launch: opus · xhigh (tier B — tier unset, default B assumed)'
has "either lists both cells"         "$OUTPUT" 'Launch: opus · xhigh (claude) or gpt-5.6-terra · xhigh (codex) (tier B)'
has "tier S/claude resolves fable high" "$OUTPUT" 'Launch: fable · high (tier S)'
has "tier A/codex resolves gpt-5.6-sol xhigh" "$OUTPUT" 'Launch: gpt-5.6-sol · xhigh (tier A)'
has "codex hint conflicts with tier S falls back to claude" "$OUTPUT" 'Launch: fable · high (tier S — driver_hint conflicts with tier S, claude only)'
has "unknown tier Q defaults to B"    "$OUTPUT" "Launch: opus · xhigh (tier B — unknown tier 'Q', default B assumed)"
has "either on one-cell tier S flags invalid hint" "$OUTPUT" 'Launch: fable · high (tier S — driver_hint either is invalid for tier S, claude only)'
has "orchestrate overrides explicit effort with marker" "$OUTPUT" 'Launch: sonnet · ultracode (tier C — effort ignored, orchestrate implies xhigh)'
has "bare legacy doc renders both cells" "$OUTPUT" 'Launch: opus · xhigh (claude) or gpt-5.6-terra · xhigh (codex) (tier B — tier unset, default B assumed)'
has "kickoff block emits bold Launch line" "$OUTPUT" '**Launch: '

in_fence="$(printf '%s\n' "$OUTPUT" | awk '/^```/{f=!f;next} f' | grep -c 'Launch:')"
[ "$in_fence" = 0 ] && ok "no Launch text inside fenced prompts" || no "Launch leaked into a fenced prompt ($in_fence occurrences)"

has "full loop renders interactive depth"  "$OUTPUT" 'run the contract'"'"'s investigation + interactive brainstorm phase with the operator first'
has "direct loop keeps direct depth"       "$OUTPUT" 'the story is fully defined — go straight to a short TDD plan'
has "direction renders no skills"          "$OUTPUT" 'Use skills: none'
# design-heavy renders TDD only — superpowers:brainstorming in a dispatched kickoff
# is the recovered "Reply 'approved'" stall (its approval gate points at an absent user).
case "$OUTPUT" in
  *'superpowers:brainstorming'*) no "design-heavy never renders the brainstorming skill" ;;
  *) ok "design-heavy never renders the brainstorming skill" ;;
esac
has "settled-by-default wording rendered"  "$OUTPUT" 'settled by default'
has "handback hard rule rendered"          "$OUTPUT" 'publish the REPLAN event (docs-only, no trailers) and release the claim branch'
has "kickoff title carries sprint identity" "$OUTPUT" "$SPRINT_NAME · Story 07: Fixture Case Doc"
has "kickoff names sprint identity"         "$OUTPUT" "Sprint identity: $SPRINT_NAME"
has "kickoff checks exact claim branch"     "$OUTPUT" "sprint/$SPRINT_NAME/07-tier-b-codex"
case "$OUTPUT" in
  *'if sprint/07-* already exists'*) no "bare story-number claim wildcard removed" ;;
  *) ok "bare story-number claim wildcard removed" ;;
esac
has "kickoff renders mailbox line"          "$OUTPUT" "Mailbox: ~/.sprint-mail/"
# Mailbox wait: resolved per harness × topology — every main-session form arms and ends the turn.
has "codex story renders arm wait line"     "$OUTPUT" "Mailbox wait: post your question, then \`~/.codex/skills/sprint-orchestrator/sprint-mail.sh arm --harness codex $SPRINT 07-{SSS}-reply.md 1800\`"
has "codex arm line ends the turn"          "$OUTPUT" "END YOUR TURN — the armed Stop hook wakes you on the reply"
has "claude story renders arm wait line"    "$OUTPUT" "\`~/.claude/skills/sprint-orchestrator/sprint-mail.sh arm --harness claude $SPRINT 08-{SSS}-reply.md 1800\`"
case "$OUTPUT" in
  *'as a background task'*) no "no background-task wait rendered" ;;
  *) ok "no background-task wait rendered" ;;
esac
has "mailbox line names the sprint"         "$OUTPUT" "/$SPRINT_NAME/ — post evidence, questions, and your terminal outcome"
# Reviews & approvals route to the orchestrator, never the terminal — the of.ru "approve spec"
# stall (July 2026) invented a user-facing spec gate the plan never asked for.
has "kickoff routes reviews to orchestrator" "$OUTPUT" "the sprint orchestrator is your only counterparty"
has "kickoff bans terminal approvals"        "$OUTPUT" "never seek approval from"
has "kickoff marks kickoff decisions approved" "$OUTPUT" "already approved — do not re-open them as a new gate"
case "$OUTPUT" in
  *"Resume grant:"*) no "ordinary kickoffs carry no resume grant" ;;
  *) ok "ordinary kickoffs carry no resume grant" ;;
esac
case "$OUTPUT" in
  *'These run in parallel'*) no "unconditional parallel sentence removed" ;;
  *) ok "unconditional parallel sentence removed" ;;
esac
has "dispatch constraint rendered"          "$OUTPUT" "merge-order-independent"
has "hard rule carries grant carve-out"     "$OUTPUT" "stop (unless this kickoff carries a resume grant)"
has "hard rule keeps exact-branch clause"   "$OUTPUT" "check, create, and release only that exact branch"
case "$OUTPUT" in *"are SETTLED"*) no "old SETTLED wording gone";; *) ok "old SETTLED wording gone";; esac

# ---- topology: required input, fail-closed ----
"$WH" "$SPRINT" 1 >/dev/null 2>&1 && no "missing --topology refused" || ok "missing --topology refused"
"$WH" "$SPRINT" 1 --topology desk >/dev/null 2>&1 && no "unknown topology refused" || ok "unknown topology refused"

# ---- subagent pass: non-arming fallback, loop: direct only ----
SERR="$(mktemp)"
SUB="$("$WH" "$SPRINT" 1 --topology subagent 2>"$SERR")"
# The load-bearing pin: a rendered subagent kickoff never arms — either harness.
case "$SUB" in *'arm --harness'*) no "subagent kickoffs never contain arm --harness" ;; *) ok "subagent kickoffs never contain arm --harness" ;; esac
case "$SUB" in *'sprint-mail.sh arm'*) no "subagent kickoffs carry no arm command at all" ;; *) ok "subagent kickoffs carry no arm command at all" ;; esac
has "subagent fallback wording rendered"  "$SUB" "Do not pretend to wait"
has "subagent form names the topology"    "$SUB" "you are an in-session subagent"
has "subagent header names the audience"  "$SUB" "kickoff for an in-session subagent"
has "subagent pass renders direct codex story"  "$SUB" "## 07 — tier-b-codex"
has "subagent pass renders direct claude story" "$SUB" "## 08 — tier-c-deviation"
case "$SUB" in *'## 20 — full-loop'*) no "subagent pass skips loop: full stories" ;; *) ok "subagent pass skips loop: full stories" ;; esac
SERRTXT="$(cat "$SERR")"
has "skip note names the full story"      "$SERRTXT" "20-full-loop.md"
has "skip note says render main-session"  "$SERRTXT" "render it main-session"

# ---- subagent pass with zero direct stories: exit 2, says why ----
Z="$("$WH" "$SPRINT" 3 --topology subagent 2>&1)"; rc=$?
[ "$rc" = "2" ] && case "$Z" in *"only 'loop: direct'"*) true ;; *) false ;; esac \
  && ok "zero-direct subagent pass exits 2 naming the filter" \
  || no "zero-direct subagent pass exits 2 naming the filter (rc=$rc out=$Z)"

# ---- Unresolved feedback events: warn on stderr, recap line on stdout ----
cat > "$SPRINT/STORY-FEEDBACK.md" <<'EOF'
# Story feedback

## REPLAN — rp-20260701-01 — Story 07
- Premise as written: fixture premise
- Contradicting evidence: fixture
- Blast radius: fixture
- Recommendation: fixture

## RESOLUTION — rp-20260701-01
- Resolution: fixture resolved

## REPLAN — rp-20260702-01 — Story 07
- Premise as written: fixture second premise
- Contradicting evidence: fixture
- Blast radius: fixture
- Recommendation: fixture

## DIRECTION — dr-20260702-02 — Story 09
- Dossier: docs/sprints/fixture/dossier-09.md
- Recommendation: fixture

## DISPOSED — dp-20260714-03-1 — Story 03
- Outcome: cut
- Cleanup: fixture
- Reason: fixture
EOF

WERR="$(mktemp)"
WOUT="$("$WH" "$SPRINT" 1 --topology main-session 2>"$WERR")"
WERRTXT="$(cat "$WERR")"
has "warning names unresolved replan id"    "$WERRTXT" 'rp-20260702-01 (Story 07)'
has "warning names unresolved direction id" "$WERRTXT" 'dr-20260702-02 (Story 09)'
has "warning names unresolved disposed id"  "$WERRTXT" 'dp-20260714-03-1 (Story 03)'
case "$WERRTXT" in *rp-20260701-01*) no "resolved id not warned";; *) ok "resolved id not warned";; esac
has "recap carries the unresolved line"     "$WOUT"    '> **Unresolved feedback events**'
case "$WOUT" in *"wave-handoffs: WARNING"*) no "stderr warning stays off stdout";; *) ok "stderr warning stays off stdout";; esac

cat >> "$SPRINT/STORY-FEEDBACK.md" <<'EOF'

## RESOLUTION — rp-20260702-01
- Resolution: fixture

## RESOLUTION — dr-20260702-02
- Resolution: fixture

## RESOLUTION — dp-20260714-03-1
- Resolution: fixture
EOF
RERR="$(mktemp)"
"$WH" "$SPRINT" 1 --topology main-session >/dev/null 2>"$RERR"
[ -s "$RERR" ] && no "no warning when all events resolved (got: '$(cat "$RERR")')" || ok "no warning when all events resolved"

# ---- --target: whole-sheet harness override (all feedback resolved above → clean stderr) ----
KIMI="$("$WH" "$SPRINT" 1 --topology main-session --target kimi 2>/dev/null)"
has "kimi target renders the cron wait form" "$KIMI" "Mailbox wait: you are a Kimi session — Kimi has no Stop-hook wait."
has "kimi wait form carries the full helper path" "$KIMI" "\`~/.agents/skills/sprint-orchestrator/sprint-mail.sh unread $SPRINT '07-{SSS}-reply.md'\`"
has "kimi wait form blocks the goal"        "$KIMI" "Then mark your goal blocked"
has "kimi wait form resumes via UpdateGoal" "$KIMI" "resume the waiter's goal with UpdateGoal active"
has "kimi wait form uses an epoch deadline" "$KIMI" "stat -f %m"
has "kimi target renders the ~/.agents contract path" "$KIMI" "Execution contract: ~/.agents/skills/agent-handoff/EXECUTION.md"
has "kimi target renders the advisory Launch line" "$KIMI" "Launch: Kimi session · model per session config (tier B advisory — the ladder has a Kimi cell only at tier S)"
has "kimi tier S renders the kimi-k3 cell"      "$KIMI" "Launch: Kimi session · kimi-k3 · high (tier S)"
has "kimi sheet header notes the override"  "$KIMI" '**`--target kimi` applied**'
case "$KIMI" in *'arm --harness'*) no "kimi sheet contains no arm --harness" ;; *) ok "kimi sheet contains no arm --harness" ;; esac
case "$KIMI" in *'~/.claude/skills/agent-handoff/EXECUTION.md'*) no "kimi sheet carries no claude contract path" ;; *) ok "kimi sheet carries no claude contract path" ;; esac
case "$KIMI" in *'~/.codex/skills/agent-handoff/EXECUTION.md'*) no "kimi sheet carries no codex contract path" ;; *) ok "kimi sheet carries no codex contract path" ;; esac

CX="$("$WH" "$SPRINT" 1 --topology main-session --target codex 2>/dev/null)"
case "$CX" in *'~/.claude/skills/agent-handoff/EXECUTION.md'*) no "codex target forces the codex contract path on every story" ;; *) ok "codex target forces the codex contract path on every story" ;; esac
has "codex target forces a claude-hint story to the codex cell" "$CX" "Launch: gpt-5.6-luna · medium (tier C)"

"$WH" "$SPRINT" 1 --topology main-session --target desk >/dev/null 2>&1 \
  && no "unknown --target refused" || ok "unknown --target refused"
"$WH" "$SPRINT" 1 --topology subagent --target kimi >/dev/null 2>&1 \
  && no "--target with subagent topology refused" || ok "--target with subagent topology refused"
"$WH" "$SPRINT" 1 --topology main-session --target >/dev/null 2>&1 \
  && no "bare --target refused" || ok "bare --target refused"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
