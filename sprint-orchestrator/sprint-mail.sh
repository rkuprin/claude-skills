#!/usr/bin/env bash
# sprint-mail.sh — transient executor↔supervisor mail for one sprint.
#
#   sprint-mail.sh post <sprint-dir> <NN> <kind> [<file>|-]
#   sprint-mail.sh list <sprint-dir> [<NN>]
#   sprint-mail.sh wait <sprint-dir> <name-or-glob> [<timeout-seconds>]
#   sprint-mail.sh arm --harness <codex|claude> <sprint-dir> <name-or-glob(s)> [<timeout-seconds>]
#   sprint-mail.sh disarm <sprint-dir> [--stale]
#   sprint-mail.sh unread <sprint-dir> <name-or-glob(s)>
#   sprint-mail.sh seen <sprint-dir> <file>...
#
# Mail lives in ${SPRINT_MAIL_ROOT:-~/.sprint-mail}/<repo-basename>/<sprint-basename>/
# — outside every worktree. It is NEVER state: story state stays git-derived
# (sprint-status.sh never reads it). Files are NN-SSS-<kind>.md, append-only.
#
# Sequences are split by sender, so allocation needs no locks (bash 3.2, no flock):
#   executor counter: evidence | question | concluded
#   reply:            reuses the story's newest unanswered question's SSS
#   supervisor:       note (own counter)
# `concluded` bodies must open with:  outcome: merged|pr-ready|handback|blocked|failed|dossier
#
# `arm --harness codex|claude` registers a reactive wait for that harness's Stop
# hook (codex-stop-wait.sh / claude-stop-wait.sh): one record per worktree under
# $MAIL_ROOT/.codex-waits/, four lines — worktree root, absolute glob(s), timeout,
# absolute cursor path. `--harness` selects which harness's Stop reference must
# already exist (a reference is not proof the hook is active — installers own
# that). `disarm` removes this worktree's record. Kimi sessions do not arm —
# Kimi has no Stop-hook wait; they wait via recurring cron sweeps (see
# sprint-orchestrator/SKILL.md 'Supervising the Wave').
# `arm` also warns (never refuses) when the session it runs in looks like a
# different harness than --harness names — detection walks the ancestor chain's
# full command lines, nearest harness ancestor wins. SPRINT_MAIL_ASSUME_HARNESS
# (codex|claude|kimi|none) overrides detection; it exists for tests.
#
# `unread`/`seen` are a durable per-consumer read-cursor: `unread` lists mail
# matching the glob(s) minus this cwd's cursor; `seen` appends read basenames.
# The cursor lives at <mail_dir>/.read/<cksum of cwd>, is namespaced per sprint,
# and is NEVER state — sprint-status.sh never reads it, deleting it loses nothing.
set -euo pipefail

MAIL_ROOT="${SPRINT_MAIL_ROOT:-$HOME/.sprint-mail}"
POLL="${SPRINT_MAIL_POLL:-20}"

usage() {
  cat >&2 <<'EOF'
usage: sprint-mail.sh post <sprint-dir> <NN> <evidence|question|concluded|reply|note> [<file>|-]
       sprint-mail.sh list <sprint-dir> [<NN>]
       sprint-mail.sh wait <sprint-dir> <name-or-glob> [<timeout-seconds>]
       sprint-mail.sh arm --harness <codex|claude> <sprint-dir> <name-or-glob(s)> [<timeout-seconds>]
       sprint-mail.sh disarm <sprint-dir> [--stale]
       sprint-mail.sh unread <sprint-dir> <name-or-glob(s)>
       sprint-mail.sh seen <sprint-dir> <file>...
EOF
  exit 2
}
err() { echo "sprint-mail: $1" >&2; exit 2; }

cmd="${1:-}"
# `arm` takes a required --harness <codex|claude> immediately after the command
# (the kickoff always knows the target harness). Pull it out before positional
# parsing so sprint-dir/glob/timeout stay positional exactly like every other
# subcommand.
harness=""
if [ "$cmd" = "arm" ] && [ "${2:-}" = "--harness" ]; then
  harness="${3:-}"
  case "$harness" in
    codex|claude) ;;
    kimi) err "arm refuses kimi — Kimi has no Stop-hook wait; a Kimi session waits via a recurring cron sweep (see the kickoff's Mailbox wait line or sprint-orchestrator/SKILL.md 'Supervising the Wave')" ;;
    *) err "arm --harness needs 'codex' or 'claude' (got: ${harness:-<empty>})" ;;
  esac
  shift 3; set -- arm "$@"
fi
sprint_dir="${2:-}"
[ -n "$cmd" ] && [ -n "$sprint_dir" ] || usage

repo_name() {
  local common
  common="$(git rev-parse --git-common-dir 2>/dev/null)" \
    || err "not inside a git repo — run from the project so the mailbox can be namespaced by repo"
  common="$(cd "$common" && pwd)"
  basename "$(dirname "$common")"
}
repo="$(repo_name)"
mail_dir="$MAIL_ROOT/$repo/$(basename "$sprint_dir")"

# Stable per-worktree consumer identity (empty outside a worktree). The cursor
# and wait records key on this so a consumer that cd's into a subdirectory does
# not fragment its cursor. One mailbox consumer per worktree.
consumer="$(git rev-parse --show-toplevel 2>/dev/null)" \
  && consumer="$(cd "$consumer" && pwd -P)" || consumer=""

next_seq() {  # $1=story  $2=ERE matching the kinds sharing this counter
  local max
  max="$(ls "$mail_dir" 2>/dev/null \
    | sed -n -E "s/^$1-([0-9]{3})-($2)\.md\$/\1/p" | sort -n | tail -1)"
  printf '%03d' "$(( 10#${max:-0} + 1 ))"
}

cursor_file() {  # per-consumer read-cursor path, keyed by the worktree root
  # Lives inside the mail dir, so it is namespaced per sprint and disposed with
  # the mailbox. cksum of the worktree root is a stable, coreutils-portable,
  # fixed-length key; the cursor is transient — never sprint state.
  printf '%s\n' "$mail_dir/.read/$(printf '%s\n' "$consumer" | cksum | cut -d' ' -f1)"
}

# detect_harness — best-effort identification of the harness whose session this
# process runs in, for the arm mismatch warning. The codex CLI presents as
# `node …/bin/codex` (comm alone reads `node`), so match argv[0]'s basename AND
# the full command line; Codex.app helpers carry a capital-C `Codex` name. The
# NEAREST harness ancestor wins: a codex exec executor spawned by a Kimi
# supervisor nests under kimi-code, and it is the codex session that arms.
detect_harness() {
  local assume="${SPRINT_MAIL_ASSUME_HARNESS:-}"
  [ "$assume" = "none" ] && return 0
  [ -n "$assume" ] && { printf '%s\n' "$assume"; return 0; }
  local pid="$$" ppid cmd base
  while [ -n "$pid" ] && [ "$pid" != "1" ]; do
    ppid="$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')"
    [ -n "$ppid" ] || break
    cmd="$(ps -o command= -p "$ppid" 2>/dev/null)" || break
    base="$(basename "$(printf '%s\n' "$cmd" | awk '{print $1}')")"
    case "$base" in
      codex|claude|kimi|Codex) printf '%s\n' "$base" | tr 'A-Z' 'a-z'; return 0 ;;
    esac
    case "$cmd" in
      */bin/codex\ *|*/bin/codex)   printf 'codex\n';  return 0 ;;
      */bin/claude\ *|*/bin/claude) printf 'claude\n'; return 0 ;;
      */bin/kimi\ *|*/bin/kimi)     printf 'kimi\n';   return 0 ;;
    esac
    pid="$ppid"
  done
}

prune_stale() {  # $1=waits_dir — drop records whose identity dir is gone or which are long expired
  local wd="$1" f id ts age now
  now="$(date +%s)"
  for f in "$wd"/*; do
    [ -f "$f" ] || continue
    id="$(sed -n 1p "$f")"
    [ -d "$id" ] || { rm -f "$f"; continue; }               # dead worktree/cwd → orphan
    ts="$(sed -n 3p "$f")"; case "$ts" in ''|*[!0-9]*) ts=1800 ;; esac
    age=$(( now - $(stat -f %m "$f" 2>/dev/null || echo "$now") ))
    if [ "$age" -gt $(( ts * 2 )) ]; then rm -f "$f"; fi     # long past budget → stale (if-form: a false && would kill set -e)
  done
}

case "$cmd" in
  post)
    nn="${3:-}"; kind="${4:-}"; src="${5:--}"
    [ -n "$nn" ] && [ -n "$kind" ] || usage
    echo "$nn" | grep -qE '^[0-9]+[a-z]?$' || err "story must look like 07 or 06b (got: $nn)"
    [ "$src" = "-" ] || [ -f "$src" ] || err "cannot read message body: $src — pass an existing file or - for stdin"
    body="$(if [ "$src" = "-" ]; then cat; else cat "$src"; fi)"
    case "$kind" in
      evidence|question|concluded)
        if [ "$kind" = "concluded" ]; then
          printf '%s\n' "$body" | head -1 \
            | grep -qE '^outcome: (merged|pr-ready|handback|blocked|failed|dossier)$' \
            || err "a concluded message must open with 'outcome: merged|pr-ready|handback|blocked|failed|dossier'"
        fi
        seq="$(mkdir -p "$mail_dir"; next_seq "$nn" 'evidence|question|concluded')" ;;
      reply)
        mkdir -p "$mail_dir"
        seq="$(ls "$mail_dir" 2>/dev/null \
          | sed -n -E "s/^$nn-([0-9]{3})-question\.md\$/\1/p" | sort -n \
          | while read -r s; do [ -e "$mail_dir/$nn-$s-reply.md" ] || echo "$s"; done | tail -1)"
        [ -n "$seq" ] || err "no open question for story $nn — a reply answers one"
        ;;
      note)
        seq="$(mkdir -p "$mail_dir"; next_seq "$nn" 'note')" ;;
      *) err "unknown kind: $kind" ;;
    esac
    out="$mail_dir/$nn-$seq-$kind.md"
    tmp="$mail_dir/.tmp.$$"
    printf '%s\n' "$body" > "$tmp" && mv "$tmp" "$out"
    printf '%s\n' "$out"
    ;;
  list)
    nn="${3:-}"
    [ -d "$mail_dir" ] || exit 0
    ls -tr "$mail_dir" | grep -E "^${nn:-[0-9]+[a-z]?}-[0-9]{3}-" \
      | sed "s|^|$mail_dir/|" || true
    ;;
  wait)
    pat="${3:-}"; timeout="${4:-1800}"
    [ -n "$pat" ] || usage
    elapsed=0
    while :; do
      for f in "$mail_dir"/$pat; do
        [ -e "$f" ] && { printf '%s\n' "$f"; exit 0; }
      done
      [ "$elapsed" -ge "$timeout" ] && exit 1
      sleep "$POLL"; elapsed=$((elapsed + POLL))
    done
    ;;
  arm)
    pat="${3:-}"; timeout="${4:-1800}"
    [ -n "$pat" ] || usage
    [ -n "$harness" ] || err "arm requires --harness <codex|claude> immediately after 'arm' — the kickoff names the target harness"
    [ -n "$consumer" ] || err "not inside a git worktree — mailbox waits are keyed per worktree; run from the project worktree"
    # An armed record only works if the named harness's Stop hook is wired —
    # otherwise the turn ends and nothing ever wakes, the exact orphaned-wait
    # failure arm exists to prevent. A textual reference is NOT proof the hook is
    # active (Claude: disableAllHooks / managed policy; Codex: silent-skip until
    # trusted) — the installers own activation; arm only verifies the reference
    # exists in the expected place. Refuse loudly instead of arming a dead wait.
    case "$harness" in
      codex)
        ref="${CODEX_HOME:-$HOME/.codex}/hooks.json"
        grep -q "codex-stop-wait.sh" "$ref" 2>/dev/null \
          || err "codex Stop hook not referenced in $ref — run sprint-orchestrator/install-codex-hook.sh once on this machine, or take the contract's no-wait fallback instead of arming" ;;
      claude)
        cfg="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
        grep -q "claude-stop-wait.sh" "$cfg/settings.json" "$cfg/settings.local.json" 2>/dev/null \
          || err "claude Stop hook not referenced in $cfg/settings.json — run sprint-orchestrator/install-claude-hook.sh once on this machine, or take the contract's no-wait fallback instead of arming" ;;
    esac
    detected="$(detect_harness)"
    if [ -n "$detected" ] && [ "$detected" != "$harness" ]; then
      echo "sprint-mail: warning: arming --harness $harness but the nearest harness ancestor looks like $detected — the wait record is harness-agnostic and will still fire; check the kickoff's harness matches this session" >&2
    fi
    echo "$timeout" | grep -qE '^[0-9]+$' || err "timeout must be whole seconds (got: $timeout)"
    case "$pat" in
      */*|*$'\n'*) err "pattern is a mail filename or glob, not a path (got: $pat)" ;;
    esac
    waits_dir="$MAIL_ROOT/.codex-waits"
    mkdir -p "$waits_dir"
    prune_stale "$waits_dir"
    for f in "$waits_dir"/*; do
      [ -f "$f" ] || continue
      [ "$(sed -n 1p "$f")" = "$consumer" ] \
        && err "a wait is already armed for this worktree — run 'sprint-mail.sh disarm' first"
    done
    abs=""
    set -f
    for p in $pat; do abs="$abs${abs:+ }$mail_dir/$p"; done
    set +f
    cur="$(cursor_file)"
    rec="$waits_dir/wait-$$-$(date +%s)"
    tmp="$waits_dir/.tmp.$$"
    printf '%s\n%s\n%s\n%s\n' "$consumer" "$abs" "$timeout" "$cur" > "$tmp" && mv "$tmp" "$rec"
    printf '%s\n' "$rec"
    ;;
  disarm)
    waits_dir="$MAIL_ROOT/.codex-waits"
    if [ "${3:-}" = "--stale" ]; then prune_stale "$waits_dir"; exit 0; fi
    [ -n "$consumer" ] || err "not inside a git worktree — mailbox waits are keyed per worktree"
    for f in "$waits_dir"/*; do
      [ -f "$f" ] || continue
      [ "$(sed -n 1p "$f")" = "$consumer" ] && rm -f "$f"
    done
    ;;
  unread)
    pat="${3:-}"
    [ -n "$pat" ] || usage
    [ -n "$consumer" ] || err "not inside a git worktree — mailbox cursors are keyed per worktree; run from the project worktree"
    [ -d "$mail_dir" ] || exit 0
    cur="$(cursor_file)"
    # oldest-first, same order as `list`; ls omits the dot-cursor and .tmp litter
    ls -tr "$mail_dir" 2>/dev/null | while IFS= read -r f; do
      matched=0
      set -f
      for p in $pat; do case "$f" in $p) matched=1; break ;; esac; done
      set +f
      [ "$matched" = 1 ] || continue
      grep -qxF "$f" "$cur" 2>/dev/null && continue
      printf '%s/%s\n' "$mail_dir" "$f"
    done
    ;;
  seen)
    shift 2  # drop cmd + sprint_dir; the rest are files (paths or basenames)
    [ "$#" -ge 1 ] || usage
    [ -n "$consumer" ] || err "not inside a git worktree — mailbox cursors are keyed per worktree; run from the project worktree"
    mkdir -p "$mail_dir/.read"
    cur="$(cursor_file)"
    for f in "$@"; do
      bn="$(basename "$f")"
      grep -qxF "$bn" "$cur" 2>/dev/null || printf '%s\n' "$bn" >> "$cur"
    done
    ;;
  *) usage ;;
esac
