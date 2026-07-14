#!/usr/bin/env bash
# wave-handoffs.sh — render one wave's ready-to-paste kickoffs into a single file.
#
#   wave-handoffs.sh docs/sprints/<sprint> <wave>
#
# Emits, to stdout, a Markdown document with:
#   - a recap of the wave (one line per story: number, title, execution mode,
#     driver hint, and the first line of the story's Objective), and
#   - one fenced, ready-to-paste `agent-handoff` story-execution kickoff per
#     story in that wave, every value resolved from the story doc's frontmatter
#     and its `/goal` line.
#
# The kickoff shape mirrors agent-handoff/SKILL.md "Mode: story-execution" — that
# skill file is the source of truth; keep this template in sync with it.
#
# Redirect to a file to get the wave's single handoff sheet, e.g.:
#   wave-handoffs.sh docs/sprints/2026-07-07-report-delivery-sprint 4 > ~/.handoffs/reports-v2-wave4.md
set -euo pipefail

sprint_dir="${1:-}"
wave="${2:-}"
[ -n "$sprint_dir" ] && [ -n "$wave" ] \
  || { echo "wave-handoffs: usage: wave-handoffs.sh docs/sprints/<sprint> <wave>" >&2; exit 2; }
[ -d "$sprint_dir" ] \
  || { echo "wave-handoffs: no such directory: $sprint_dir — run this from the repo root and pass a sprint dir, e.g. docs/sprints/2026-07-07-report-delivery-sprint" >&2; exit 2; }

sprint_name="$(basename "$sprint_dir")"

# Mailbox path namespaced by repo (worktree-safe); mirrors sprint-mail.sh's derivation.
repo_name="$(git rev-parse --git-common-dir 2>/dev/null)" \
  && repo_name="$(basename "$(dirname "$(cd "$repo_name" && pwd)")")" \
  || repo_name="$(basename "$(pwd)")"
mailbox="~/.sprint-mail/$repo_name/$sprint_name/"

# Lines strictly between the first `---` and the next `---` (the YAML frontmatter).
frontmatter() { awk 'seen&&/^---[[:space:]]*$/{exit} /^---[[:space:]]*$/{seen=1;next} seen' "$1"; }

# A scalar frontmatter value: strip the key, a trailing ` # comment`, surrounding
# whitespace, and one layer of quotes. Only used for comment-free scalar keys.
fm_get() {
  frontmatter "$1" | grep -m1 "^$2:[[:space:]]" \
    | sed -E "s/^$2:[[:space:]]*//; s/[[:space:]]+#.*$//; s/[[:space:]]+$//; s/^\"(.*)\"$/\1/; s/^'(.*)'$/\1/" || true
}

# First non-empty line after the `## Objective` heading.
objective_line() { awk '/^##[[:space:]]+Objective[[:space:]]*$/{f=1;next} f&&NF{print;exit}' "$1"; }

# The story's single `/goal …` line (inside the Goal fenced block).
goal_line() { grep -m1 '^/goal ' "$1" || true; }

# ---- Launch line: tier row × driver column, resolved against today's ladder ----
# Keep this table in sync with the ladder in SKILL.md (test-wave-handoffs.sh pins the output).
launch_line() {   # $1 = story doc path -> prints one operator-facing Launch line
  local doc="$1" tier effort orchestrate driver marker="" c_model x_model depth c_eff x_eff
  tier="$(fm_get "$doc" tier)"; effort="$(fm_get "$doc" effort)"
  orchestrate="$(fm_get "$doc" orchestrate)"; driver="$(fm_get "$doc" driver_hint)"
  if [ -z "$tier" ]; then tier="B"; marker=" — tier unset, default B assumed"; fi
  case "$tier" in
    S) c_model="fable";  x_model="";              depth="high"  ;;
    A) c_model="";       x_model="gpt-5.6-sol";   depth="xhigh" ;;
    B) c_model="opus";   x_model="gpt-5.6-terra"; depth="xhigh" ;;
    C) c_model="sonnet"; x_model="gpt-5.6-luna";  depth="high"  ;;
    *) c_model="opus";   x_model="gpt-5.6-terra"; depth="xhigh"
       marker=" — unknown tier '$tier', default B assumed"; tier="B" ;;
  esac
  [ -n "$effort" ] && depth="$effort"
  c_eff="$depth"; x_eff="$depth"
  if [ "$orchestrate" = "true" ]; then
    c_eff="ultracode"; x_eff="ultra"
    [ "$x_model" = "gpt-5.6-luna" ] && x_model="gpt-5.6-terra"   # Luna has no ultra
    [ -n "$effort" ] && marker="$marker — effort ignored, orchestrate implies xhigh"
  fi
  case "$driver" in
    codex)  [ -n "$x_model" ] || { driver="claude"; marker="$marker — driver_hint conflicts with tier S, claude only"; } ;;
    claude) [ -n "$c_model" ] || { driver="codex";  marker="$marker — driver_hint conflicts with tier A, codex only"; } ;;
  esac
  case "$driver" in
    codex)  printf 'Launch: %s · %s (tier %s%s)\n' "$x_model" "$x_eff" "$tier" "$marker" ;;
    claude) printf 'Launch: %s · %s (tier %s%s)\n' "$c_model" "$c_eff" "$tier" "$marker" ;;
    *)  if [ -z "$x_model" ]; then
          [ "$driver" = "either" ] && marker="$marker — driver_hint either is invalid for tier S, claude only"
          printf 'Launch: %s · %s (tier %s%s)\n' "$c_model" "$c_eff" "$tier" "$marker"
        elif [ -z "$c_model" ]; then
          [ "$driver" = "either" ] && marker="$marker — driver_hint either is invalid for tier A, codex only"
          printf 'Launch: %s · %s (tier %s%s)\n' "$x_model" "$x_eff" "$tier" "$marker"
        else
          printf 'Launch: %s · %s (claude) or %s · %s (codex) (tier %s%s)\n' \
            "$c_model" "$c_eff" "$x_model" "$x_eff" "$tier" "$marker"
        fi ;;
  esac
}

# Collect the wave's docs, ordered by filename (06b sorts after 06, before 07).
docs=()
for doc in "$sprint_dir"/[0-9]*.md; do
  [ -e "$doc" ] || continue
  case "$(basename "$doc")" in 00-*|*.CLAIMED.md) continue ;; esac
  [ "$(fm_get "$doc" wave)" = "$wave" ] || continue
  docs+=("$doc")
done

[ "${#docs[@]}" -gt 0 ] \
  || { echo "wave-handoffs: no story docs with 'wave: $wave' in $sprint_dir" >&2; exit 2; }

# ---- Unresolved feedback events: warn, never block (operator's explicit choice) ----
feedback="$sprint_dir/STORY-FEEDBACK.md"
unresolved=""
if [ -f "$feedback" ]; then
  unresolved="$(awk '
    /^## (REPLAN|DIRECTION|DISPOSED) — /{ids[$4]=$7}
    /^## RESOLUTION — /{resolved[$4]=1}
    END{for (id in ids) if (!(id in resolved)) printf "%s (Story %s), ", id, ids[id]}' "$feedback")"
  unresolved="${unresolved%, }"
fi
[ -n "$unresolved" ] \
  && printf 'wave-handoffs: WARNING: unresolved feedback events — resolve via /sprint-orchestrator before kickoff: %s\n' "$unresolved" >&2

# ---- Header + recap -------------------------------------------------------
printf '# %s — Wave %s handoffs\n\n' "$sprint_name" "$wave"
printf '_Generated by `wave-handoffs.sh` from the story docs. Each fenced block below is a ready-to-paste '
printf '`agent-handoff` (story-execution) kickoff — paste each into its own executor session. The **Launch** line above '
printf 'each block is a recommendation resolved from the story'"'"'s tier and driver; capability, your explicit choice, and '
printf 'current availability override it at paste time. The '
printf 'heavy detail lives in the referenced story doc, not here._\n\n'

printf '## Wave %s at a glance\n\n' "$wave"
for doc in "${docs[@]}"; do
  story="$(fm_get "$doc" story)"
  title="$(fm_get "$doc" title)"
  execution="$(fm_get "$doc" execution)"
  driver_hint="$(fm_get "$doc" driver_hint)"
  obj="$(objective_line "$doc")"
  printf -- '- **%s — %s** _(%s, driver: %s)_ — %s\n' "$story" "$title" "$execution" "$driver_hint" "$obj"
  printf -- '  - %s\n' "$(launch_line "$doc")"
done
[ -n "$unresolved" ] \
  && printf '\n> **Unresolved feedback events** — resolve via `/sprint-orchestrator` before kickoff: %s\n' "$unresolved"
printf '\nStories above are dispatch candidates — fire in parallel only those that are ownership-disjoint\n'
printf 'and merge-order-independent; see `00-overview.md` for ownership and merge order.\n'

# ---- One kickoff per story ------------------------------------------------
for doc in "${docs[@]}"; do
  story="$(fm_get "$doc" story)"
  title="$(fm_get "$doc" title)"
  conversation="$(fm_get "$doc" conversation)"
  sprint_fm="$(fm_get "$doc" sprint)"
  branch="$(fm_get "$doc" branch)"
  execution="$(fm_get "$doc" execution)"
  loop="$(fm_get "$doc" loop)"
  flow="$(fm_get "$doc" flow)"
  driver_hint="$(fm_get "$doc" driver_hint)"
  goal="$(goal_line "$doc")"
  doc_rel="$sprint_dir/$(basename "$doc")"
  [ -n "$branch" ] || branch="sprint/$(basename "$doc" .md)"

  case "$execution" in
    autonomous) exec_mode="AUTONOMOUS — merge, deploy, verify on prod." ;;
    stop-at-pr) exec_mode="STOP AT PR — DO NOT MERGE OR DEPLOY." ;;
    *)          exec_mode="$execution" ;;
  esac
  case "$loop" in
    full)   depth="run the contract's investigation + interactive brainstorm phase with the operator first" ;;
    direct) depth="the story is fully defined — go straight to a short TDD plan" ;;
    *)      depth="$loop" ;;
  esac
  case "$driver_hint" in
    codex) contract="~/.codex/skills/agent-handoff/EXECUTION.md" ;;
    *)     contract="~/.claude/skills/agent-handoff/EXECUTION.md" ;;
  esac
  skills="superpowers:test-driven-development"
  [ "$flow" = "design-heavy" ] && skills="superpowers:brainstorming, superpowers:test-driven-development"
  [ "$flow" = "direction" ] && skills="none"

  printf '\n---\n\n## %s — %s\n\n' "$story" "$title"
  printf '**%s**\n\n' "$(launch_line "$doc")"
  printf '```\n'
  printf '%s\n\n' "${conversation:-${sprint_fm:-$sprint_name} · Story $story}"
  printf 'You are executing ONE story end-to-end.\n'
  printf 'EXECUTION MODE: %s\n' "$exec_mode"
  printf 'Sprint identity: %s. Designated claim branch: `%s`.\n' "${sprint_fm:-$sprint_name}" "$branch"
  printf 'Mailbox: %s — post evidence, questions, and your terminal outcome per the contract'"'"'s Mailbox section.\n' "$mailbox"
  printf 'Read first: %s, %s/00-overview.md, %s/STORY-FEEDBACK.md, and repo conventions\n' "$doc_rel" "$sprint_dir" "$sprint_dir"
  printf '(AGENTS.md / CLAUDE.md). If any are absent from this worktree, read them from trunk with\n'
  printf '`git show origin/main:<path>` — never copy them in. Product scope and decisions there are\n'
  printf 'settled by default; the operator may amend them at the brainstorm gate, and divergences follow\n'
  printf 'the contract'"'"'s handback protocol.\n'
  printf 'Execution contract: %s — follow it exactly.\n' "$contract"
  printf 'Planning depth: %s.\n' "$depth"
  printf 'Use skills: %s\n' "$skills"
  printf 'Hard rules: every commit carries `Story: %s` and `Sprint: %s` (verbatim);\n' "$story" "${sprint_fm:-$sprint_name}"
  printf 'never `git checkout main`; if designated branch `%s` already exists on any ref the story is taken — stop (unless this kickoff carries a resume grant); check, create, and release only that exact branch;\n' "$branch"
  printf 'on handback publish the REPLAN event (docs-only, no trailers) and release the claim branch;\n'
  printf 'never leave prod broken.\n\n'
  printf '%s\n' "${goal:-/goal <missing /goal line in $doc_rel>}"
  printf '```\n'
done
