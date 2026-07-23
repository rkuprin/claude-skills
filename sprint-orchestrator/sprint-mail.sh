#!/usr/bin/env bash
# sprint-mail.sh — transient executor↔supervisor mail for one sprint.
#
#   sprint-mail.sh post <sprint-dir> <NN> <kind> [<file>|-]
#   sprint-mail.sh list <sprint-dir> [<NN>]
#   sprint-mail.sh wait <sprint-dir> <name-or-glob> [<timeout-seconds>]
#   sprint-mail.sh watch <sprint-dir> <name-or-glob(s)> [<timeout-seconds>]
#   sprint-mail.sh arm --harness <codex|claude> <sprint-dir> <name-or-glob(s)> [<timeout-seconds>]
#   sprint-mail.sh supervise --harness <codex|claude|kimi> <sprint-dir>
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
# `arm --harness codex` registers a reactive wait for the Codex Stop hook
# (codex-stop-wait.sh): one record per worktree under $MAIL_ROOT/.codex-waits/,
# four lines — worktree root, absolute glob(s), timeout, absolute cursor path.
# `--harness` requires the hook's Stop reference to already exist (a reference
# is not proof the hook is active — installers own that). `disarm` removes this
# worktree's record. Claude sessions do not arm — the Claude wait is `watch`,
# launched as a harness background task (Monitor): a cursor-aware poll that
# prints exactly ONE stdout line (new mail, timeout guidance, or error — errors
# mirrored to stderr) and exits; one watch per worktree via an advisory lock in
# <mail_dir>/.watch/ (stale when its PID is dead or its age passes 2x timeout).
# Kimi sessions wait via recurring cron sweeps (see sprint-orchestrator/SKILL.md
# 'Supervising the Wave').
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
  # watch runs under a background launcher whose wake event is stdout-only, so
  # its failures must land one line on stdout too — stderr alone is a silent death.
  if [ "${cmd:-}" = "watch" ]; then
    echo "sprint-mail: bad or missing arguments — usage: sprint-mail.sh watch <sprint-dir> <name-or-glob(s)> [<timeout-seconds>]"
  fi
  cat >&2 <<'EOF'
usage: sprint-mail.sh post <sprint-dir> <NN> <evidence|question|concluded|reply|note> [<file>|-]
       sprint-mail.sh list <sprint-dir> [<NN>]
       sprint-mail.sh wait <sprint-dir> <name-or-glob> [<timeout-seconds>]
       sprint-mail.sh watch <sprint-dir> <name-or-glob(s)> [<timeout-seconds>]
       sprint-mail.sh arm --harness <codex|claude> <sprint-dir> <name-or-glob(s)> [<timeout-seconds>]
       sprint-mail.sh supervise --harness <codex|claude|kimi> <sprint-dir>
       sprint-mail.sh disarm <sprint-dir> [--stale]
       sprint-mail.sh unread <sprint-dir> <name-or-glob(s)>
       sprint-mail.sh seen <sprint-dir> <file>...
EOF
  exit 2
}
err() {
  echo "sprint-mail: $1" >&2
  # if-form, not `&&` — under set -e a false && chain would exit with the wrong status
  if [ "${cmd:-}" = "watch" ]; then echo "sprint-mail: $1"; fi
  exit 2
}

cmd="${1:-}"
# `arm` and `supervise` take a required --harness flag immediately after the
# command (the kickoff always knows the target harness). Pull it out before
# positional parsing so sprint-dir/glob/timeout stay positional exactly like
# every other subcommand. arm accepts codex|claude; supervise also accepts
# kimi (it prints a cron park instead of arming).
harness=""
case "$cmd" in
  arm|supervise)
    [ "${2:-}" = "--harness" ] \
      || err "$cmd requires --harness <codex|claude> immediately after '$cmd' — the kickoff names the target harness"
    harness="${3:-}"
    if [ "$cmd" = "supervise" ]; then
      case "$harness" in
        codex|claude|kimi) ;;
        *) err "supervise --harness needs 'codex', 'claude', or 'kimi' (got: ${harness:-<empty>})" ;;
      esac
    else
      case "$harness" in
        codex|claude) ;;
        kimi) err "arm refuses kimi — Kimi has no Stop-hook wait; a Kimi session waits via a recurring cron sweep (see the kickoff's Mailbox wait line or sprint-orchestrator/SKILL.md 'Supervising the Wave')" ;;
        *) err "arm --harness needs 'codex' or 'claude' (got: ${harness:-<empty>})" ;;
      esac
    fi
    shift 3; set -- "$cmd" "$@"
    ;;
esac
sprint_dir="${2:-}"
[ -n "$cmd" ] && [ -n "$sprint_dir" ] || usage

repo_name() {
  local common
  common="$(git rev-parse --git-common-dir 2>/dev/null)" || return 1
  common="$(cd "$common" && pwd)"
  basename "$(dirname "$common")"
}
# err at the call site, not inside repo_name: inside $(...) the watch-protocol
# stdout mirror would be swallowed by the substitution.
repo="$(repo_name)" \
  || err "not inside a git repo — run from the project so the mailbox can be namespaced by repo"
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

watch_lock() {  # advisory one-watch-per-worktree lock, keyed like the cursor
  printf '%s\n' "$mail_dir/.watch/$(printf '%s\n' "$consumer" | cksum | cut -d' ' -f1)"
}
watch_lock_stale() {  # $1=lock — stale when its PID is dead (fast path; a killed
  # watch cannot rm its own lock) or past 2x its recorded timeout (backstop for
  # PID reuse). Lock format: line 1 PID, line 2 timeout.
  local pid lt age
  pid="$(sed -n 1p "$1" 2>/dev/null)"
  case "$pid" in ''|*[!0-9]*) return 0 ;; esac   # malformed → stale
  kill -0 "$pid" 2>/dev/null || return 0
  lt="$(sed -n 2p "$1" 2>/dev/null)"; case "$lt" in ''|*[!0-9]*) lt=1800 ;; esac
  age=$(( $(date +%s) - $(stat -f %m "$1" 2>/dev/null || echo 0) ))
  [ "$age" -gt $(( lt * 2 )) ]
}

# classify_cmd — map one process's full command line to a harness name
# (codex|claude|kimi on stdout), or print nothing and return 1 when unsure.
# Pure (no ps, no env) so tests can source and drive it directly.
# argv[0]'s basename is derived in-shell: macOS basename parses options, so it
# chokes on a login shell's `-zsh`/`-bash` argv[0].
classify_cmd() {
  local cmd="$1" base
  base="${cmd%% *}"; base="${base##*/}"
  case "$base" in
    codex|claude|kimi) printf '%s\n' "$base"; return 0 ;;
    kimi-code) printf 'kimi\n';  return 0 ;;  # the Kimi CLI's running process name
    Codex*)    printf 'codex\n'; return 0 ;;  # Codex.app helpers: Codex, Codex (Renderer), Codex (Service)
  esac
  case "$cmd" in
    */bin/codex\ *|*/bin/codex)         printf 'codex\n';  return 0 ;;
    */bin/claude\ *|*/bin/claude)       printf 'claude\n'; return 0 ;;
    */bin/kimi\ *|*/bin/kimi)           printf 'kimi\n';   return 0 ;;
    */bin/kimi-code\ *|*/bin/kimi-code) printf 'kimi\n';   return 0 ;;
    *Codex\ Framework*)                 printf 'codex\n';  return 0 ;;  # Codex.app's embedded framework path
  esac
  return 1
}

# detect_harness — best-effort identification of the harness whose session this
# process runs in, for the arm mismatch warning. The codex CLI presents as
# `node …/bin/codex` (comm alone reads `node`), so classify_cmd matches argv[0]'s
# basename AND the full command line; the Kimi CLI's process name is `kimi-code`
# and Codex.app helpers carry capital-C `Codex …` names. The NEAREST harness
# ancestor wins: a codex exec executor spawned by a Kimi supervisor nests under
# kimi-code, and it is the codex session that arms.
detect_harness() {
  local assume="${SPRINT_MAIL_ASSUME_HARNESS:-}"
  [ "$assume" = "none" ] && return 0
  [ -n "$assume" ] && { printf '%s\n' "$assume"; return 0; }
  local pid="$$" ppid cmd
  while [ -n "$pid" ] && [ "$pid" != "1" ]; do
    ppid="$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')"
    [ -n "$ppid" ] || break
    cmd="$(ps -o command= -p "$ppid" 2>/dev/null)" || break
    classify_cmd "$cmd" && return 0
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
  watch)
    # Background wait for Claude sessions: the harness launcher turns stdout
    # into the wake event, so every terminal outcome is exactly ONE stdout line.
    pat="${3:-}"; timeout="${4:-1800}"
    [ -n "$pat" ] || usage
    [ -n "$consumer" ] || err "not inside a git worktree — mailbox watches are keyed per worktree; run from the project worktree"
    echo "$timeout" | grep -qE '^[0-9]+$' || err "timeout must be whole seconds (got: $timeout)"
    case "$pat" in
      */*|*$'\n'*) err "pattern is a mail filename or glob, not a path (got: $pat)" ;;
    esac
    mkdir -p "$mail_dir/.watch"
    lock="$(watch_lock)"
    if [ -f "$lock" ] && watch_lock_stale "$lock"; then rm -f "$lock"; fi
    if ! (set -C; printf '%s\n%s\n' "$$" "$timeout" > "$lock") 2>/dev/null; then
      err "a watch is already running for this worktree ($lock) — one watch per worktree; if its process is dead the next watch will prune it, or remove the lock by hand"
    fi
    trap 'rm -f "$lock"' EXIT
    cur="$(cursor_file)"
    elapsed=0
    found=""
    while :; do
      # same predicate as `unread`: glob match minus the read-cursor
      for f in $(ls -tr "$mail_dir" 2>/dev/null); do
        matched=0
        set -f
        for p in $pat; do case "$f" in $p) matched=1; break ;; esac; done
        set +f
        [ "$matched" = 1 ] || continue
        grep -qxF "$f" "$cur" 2>/dev/null && continue
        found="${found}${found:+ }$mail_dir/$f"
      done
      [ -n "$found" ] && break
      [ "$elapsed" -ge "$timeout" ] && break
      sleep "$POLL"; elapsed=$((elapsed + POLL))
    done
    if [ -n "$found" ]; then
      printf 'New sprint mail arrived: %s — a nudge, not state: sweep with sprint-mail.sh unread, mark seen, and act on what the SWEEP returns. Supervisors: re-park (sprint-mail.sh supervise) before ending the turn if the wave is still running.\n' "$found"
      exit 0
    fi
    case "$pat" in
      *-reply.md*)
        # question-wait (also wins for combined reply+note patterns: the reply
        # is the blocking need, the note match is opportunistic)
        printf 'Mailbox watch timed out after %ss with no new mail. Executors: take the contract'\''s no-reply fallback (handback/blocked) and post your terminal concluded. Supervisors: sweep, then launch a new watch if the wave is still running.\n' "$timeout" ;;
      *-note.md*)
        # dependency park — expiring is not a verdict on the gate
        printf 'Mailbox watch timed out after %ss with no new mail. This was a dependency park on a gate note — the gate is still closed. Launch the same watch again and keep parking; do NOT post a terminal concluded merely because the wait expired. Take the handback path only if the dependency'\''s premise changed.\n' "$timeout" ;;
      *-question.md*|*-concluded.md*)
        # supervisor sweep form
        printf 'Mailbox watch timed out after %ss with no new mail. Supervisors: sweep ALL new mail with sprint-mail.sh unread, then launch a new watch (sprint-mail.sh supervise --harness claude) before ending the turn if the wave is still running.\n' "$timeout" ;;
      *)
        printf 'Mailbox watch timed out after %ss with no new mail. Executors: take the contract'\''s no-reply fallback (handback/blocked) and post your terminal concluded. Supervisors: sweep, then launch a new watch if the wave is still running.\n' "$timeout" ;;
    esac
    exit 1
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
  supervise)
    [ -n "$consumer" ] || err "not inside a git worktree — mailbox waits are keyed per worktree; run from the project worktree"
    case "$harness" in
      codex|claude)
        globs='*-question.md *-concluded.md'
        budget=1800; [ "$harness" = "claude" ] && budget=10800
        abs=""
        set -f
        for p in $globs; do abs="$abs${abs:+ }$mail_dir/$p"; done
        set +f
        waits_dir="$MAIL_ROOT/.codex-waits"
        prune_stale "$waits_dir"
        for f in "$waits_dir"/*; do
          [ -f "$f" ] || continue
          [ "$(sed -n 1p "$f")" = "$consumer" ] || continue
          if [ "$(sed -n 2p "$f")" = "$abs" ]; then
            printf 'already armed: %s\n' "$f"
            exit 0
          fi
          err "a different wait is already armed for this worktree ($(sed -n 2p "$f")) — run 'sprint-mail.sh disarm' first"
        done
        exec "$0" arm --harness "$harness" "$sprint_dir" "$globs" "$budget"
        ;;
      kimi)
        cat <<EOF
Kimi supervisor park for $sprint_dir — Kimi has no Stop hook, so the wait is a recurring cron sweep. Do this now:

1. CronList. If a sweep task for this sprint already exists, stop — do not create a duplicate.
2. Otherwise CronCreate (recurring):
   cron: */5 * * * *
   prompt: "Supervisor sweep for $sprint_dir: from the project root run \`~/.agents/skills/sprint-orchestrator/sprint-mail.sh unread $sprint_dir '*-question.md *-concluded.md'\` then \`~/.agents/skills/sprint-orchestrator/sprint-mail.sh unread $sprint_dir '*'\` — read everything found, then \`seen\` it. If you found mail: act per the sprint-orchestrator skill's Supervising section (resume your goal with UpdateGoal active if you have one). When every story is DONE or DISPOSED, delete this cron task with CronDelete. If this fire arrives marked stale (7-day expiry) and the wave is still running, re-create the same task. Otherwise end the turn."
3. End your turn. With an active goal, mark it blocked first — the blocked state IS the park (an active goal's continuation turns starve cron delivery). With no active goal, simply ending the turn is the park — cron fires land whenever the session is idle.
EOF
        ;;
    esac
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
