#!/usr/bin/env bash
# test-wave-handoffs.sh — fixture stories in a temp sprint dir; assert rendered Launch lines.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
WH="$HERE/../wave-handoffs.sh"
PASS=0; FAIL=0
ok() { PASS=$((PASS+1)); printf 'ok   - %s\n' "$1"; }
no() { FAIL=$((FAIL+1)); printf 'FAIL - %s\n' "$1"; }
has() { case "$2" in *"$3"*) ok "$1";; *) no "$1 (missing: $3)";; esac; }

SPRINT="$(mktemp -d)/2026-07-10-fixture-sprint"; mkdir -p "$SPRINT"

story() {  # $1=NN $2=slug, remaining args = extra frontmatter lines
  local nn="$1" slug="$2"; shift 2
  { printf -- '---\nstory: %s\ntitle: %s\nconversation: "Story %s: Fixture Case Doc"\n' "$nn" "$slug" "$nn"
    printf 'sprint: 2026-07-10-fixture-sprint\nexecution: stop-at-pr\nflow: mechanical\nloop: direct\nwave: 1\n'
    local line; for line in "$@"; do printf '%s\n' "$line"; done
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

OUTPUT="$("$WH" "$SPRINT" 1 2>&1)" && ok "wave-handoffs runs" || { no "wave-handoffs runs"; printf '%s\n' "$OUTPUT"; }

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
has "kickoff block emits bold Launch line" "$OUTPUT" '**Launch: '

in_fence="$(printf '%s\n' "$OUTPUT" | awk '/^```/{f=!f;next} f' | grep -c 'Launch:')"
[ "$in_fence" = 0 ] && ok "no Launch text inside fenced prompts" || no "Launch leaked into a fenced prompt ($in_fence occurrences)"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
