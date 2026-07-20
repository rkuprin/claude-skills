#!/usr/bin/env bash
# wave-handoffs.sh — render one wave's ready-to-paste kickoffs into a single file.
#
#   wave-handoffs.sh docs/sprints/<sprint> <wave> --topology <main-session|subagent>
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
#   wave-handoffs.sh docs/sprints/2026-07-07-report-delivery-sprint 4 --topology main-session > ~/.handoffs/reports-v2-wave4.md
set -euo pipefail

sprint_dir="${1:-}"
wave="${2:-}"
usage="wave-handoffs: usage: wave-handoffs.sh docs/sprints/<sprint> <wave> --topology <main-session|subagent> [--target <codex|claude|kimi>]"
# Topology is a dispatch-time render input, never story frontmatter — the operator's paste
# sheet is always main-session; only the orchestrator's own in-session subagent dispatch
# renders the subagent form. Required and fail-closed: an omitted topology must error here,
# not silently render an arming kickoff a subagent could never be woken from.
[ $# -ge 4 ] && [ -n "$sprint_dir" ] && [ -n "$wave" ] && [ "${3:-}" = "--topology" ] \
  || { echo "$usage" >&2; exit 2; }
topology="$4"
case "$topology" in
  main-session|subagent) ;;
  *) echo "$usage" >&2; exit 2 ;;
esac
# --target is an optional whole-sheet harness override (paste a batch into one harness when
# capacity is tight): it switches every story's contract path, Mailbox wait form, and Launch
# cell together. Fail-closed like topology; meaningless under the subagent topology, which
# owns the wait line itself.
target=""
if [ $# -eq 6 ]; then
  [ "${5:-}" = "--target" ] || { echo "$usage" >&2; exit 2; }
  target="$6"
  case "$target" in
    codex|claude|kimi) ;;
    *) echo "$usage" >&2; exit 2 ;;
  esac
elif [ $# -ne 4 ]; then
  echo "$usage" >&2; exit 2
fi
[ -n "$target" ] && [ "$topology" = "subagent" ] && { echo "$usage" >&2; exit 2; }
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
launch_line() {   # $1 = story doc path, $2 = optional --target override -> prints one operator-facing Launch line
  local doc="$1" override="${2:-}" tier effort orchestrate driver marker="" c_model x_model depth c_eff x_eff
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
  # A kimi --target renders no ladder cell at all — a Kimi session runs its configured model.
  if [ "$override" = "kimi" ]; then
    printf 'Launch: Kimi session · model per session config (tier %s advisory — the ladder has no Kimi cell%s)\n' "$tier" "$marker"
    return
  fi
  [ -n "$override" ] && driver="$override"
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
  # Never subagent a non-direct story (loop: full needs an interactive session).
  if [ "$topology" = "subagent" ] && [ "$(fm_get "$doc" loop)" != "direct" ]; then
    printf 'wave-handoffs: skipping %s — loop: %s never runs as an in-session subagent; render it main-session\n' \
      "$(basename "$doc")" "$(fm_get "$doc" loop)" >&2
    continue
  fi
  docs+=("$doc")
done

if [ "${#docs[@]}" -eq 0 ]; then
  if [ "$topology" = "subagent" ]; then
    echo "wave-handoffs: no story docs with 'wave: $wave' in $sprint_dir — the subagent pass renders only 'loop: direct' stories" >&2
  else
    echo "wave-handoffs: no story docs with 'wave: $wave' in $sprint_dir" >&2
  fi
  exit 2
fi

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
if [ "$topology" = "subagent" ]; then
  printf '_Generated by `wave-handoffs.sh` from the story docs. Each fenced block below is a story-execution '
  printf 'kickoff for an in-session subagent (`loop: direct` stories only; skipped stories are named on stderr). '
  printf 'Subagent kickoffs render the non-arming `Mailbox wait:` — a subagent cannot end its turn and be woken. The **Launch** line above '
else
  printf '_Generated by `wave-handoffs.sh` from the story docs. Each fenced block below is a ready-to-paste '
  printf '`agent-handoff` (story-execution) kickoff — paste each into its own executor session. The **Launch** line above '
fi
printf 'each block is a recommendation resolved from the story'"'"'s tier and driver; capability, your explicit choice, and '
printf 'current availability override it at paste time. The '
printf 'heavy detail lives in the referenced story doc, not here._\n\n'
[ -n "$target" ] \
  && printf '> **`--target %s` applied** — every kickoff below renders the %s contract path, wait form, and Launch cell.\n\n' "$target" "$target"

printf '## Wave %s at a glance\n\n' "$wave"
for doc in "${docs[@]}"; do
  story="$(fm_get "$doc" story)"
  title="$(fm_get "$doc" title)"
  execution="$(fm_get "$doc" execution)"
  driver_hint="$(fm_get "$doc" driver_hint)"
  obj="$(objective_line "$doc")"
  printf -- '- **%s — %s** _(%s, driver: %s)_ — %s\n' "$story" "$title" "$execution" "$driver_hint" "$obj"
  printf -- '  - %s\n' "$(launch_line "$doc" "$target")"
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
  # The wait line and contract path resolve per story from driver_hint; a --target flag
  # overrides that for the whole sheet (kimi gets the cron form and the ~/.agents path).
  eff_driver="$driver_hint"
  [ -n "$target" ] && eff_driver="$target"
  case "$eff_driver" in
    kimi) contract="~/.agents/skills/agent-handoff/EXECUTION.md"
           mailwait='you are a Kimi session — Kimi has no Stop-hook wait. Post your question and note the post time, then use your CronCreate tool to schedule a recurring check (every 3 minutes) whose prompt reads: "Sprint mailbox wait for '"$story"'-{SSS}-reply.md: run `~/.agents/skills/sprint-orchestrator/sprint-mail.sh unread '"$sprint_dir"' '"'"''"$story"'-{SSS}-reply.md'"'"'` from the worktree. If the reply landed at or before <deadline — a literal epoch, post time + 1800s; compare against `stat -f %m` of the reply file>: read it, mark it seen, delete this cron task with CronDelete, then resume the waiter'"'"'s goal with UpdateGoal active and continue. If it landed later, or the deadline has passed with no reply: delete this cron task and take the contract'"'"'s no-reply fallback. Otherwise end the turn — the goal stays blocked." Then mark your goal blocked — this is the designed wait protocol, not a failure: the blocker is an external condition (the mailbox reply) and the cron task is the wake; an active goal'"'"'s continuation turns starve cron delivery, so the blocked state IS the park. Then END YOUR TURN — the cron nudge wakes you; never poll or background the wait.' ;;
    codex) contract="~/.codex/skills/agent-handoff/EXECUTION.md"
           mailwait='post your question, then `~/.codex/skills/sprint-orchestrator/sprint-mail.sh arm --harness codex '"$sprint_dir $story"'-{SSS}-reply.md 1800` (SSS = your question'"'"'s sequence) and END YOUR TURN — the armed Stop hook wakes you on the reply; never poll or background the wait.' ;;
    *)     contract="~/.claude/skills/agent-handoff/EXECUTION.md"
           mailwait='post your question, then `~/.claude/skills/sprint-orchestrator/sprint-mail.sh arm --harness claude '"$sprint_dir $story"'-{SSS}-reply.md 1800` (SSS = your question'"'"'s sequence) and END YOUR TURN — the armed Stop hook wakes you on the reply; never poll or background the wait.' ;;
  esac
  # Subagent topology overrides every harness form: the Stop hook never fires for an
  # in-session subagent, so an armed wait would never wake it — never render an arm here.
  if [ "$topology" = "subagent" ]; then
    mailwait='you are an in-session subagent — the Stop hook never fires for you, so you cannot end your turn and be woken. Do not pretend to wait: if you post a blocking question, treat it as no reply and take the contract'"'"'s fallback path now.'
  fi
  # design-heavy renders TDD only: the design conversation is the contract's own
  # brainstorm gate. superpowers:brainstorming is never rendered into a dispatched
  # kickoff — its user-approval gate points at a human who is not in the loop
  # (the "Reply 'approved'" stalls recovered from July 2026 Codex sessions).
  skills="superpowers:test-driven-development"
  [ "$flow" = "direction" ] && skills="none"

  printf '\n---\n\n## %s — %s\n\n' "$story" "$title"
  printf '**%s**\n\n' "$(launch_line "$doc" "$target")"
  printf '```\n'
  printf '%s\n\n' "${conversation:-${sprint_fm:-$sprint_name} · Story $story}"
  printf 'You are executing ONE story end-to-end.\n'
  printf 'EXECUTION MODE: %s\n' "$exec_mode"
  printf 'Sprint identity: %s. Designated claim branch: `%s`.\n' "${sprint_fm:-$sprint_name}" "$branch"
  printf 'Mailbox: %s — post evidence, questions, and your terminal outcome per the contract'"'"'s Mailbox section.\n' "$mailbox"
  printf 'Mailbox wait: %s\n' "$mailwait"
  printf 'Reviews & approvals: the sprint orchestrator is your only counterparty — route spec reviews,\n'
  printf 'design sign-off, and every open decision to it via the Mailbox above; never seek approval from\n'
  printf 'whoever is at this terminal. Decisions in the story doc, 00-overview.md, and this kickoff are\n'
  printf 'already approved — do not re-open them as a new gate.\n'
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
