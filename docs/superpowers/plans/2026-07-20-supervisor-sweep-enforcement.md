# Supervisor Sweep Enforcement + Wait-Machinery Guards Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close the three sprint-mail failure modes found in the 2026-07-20-remediation-sprint-1 post-mortem: the Kimi supervisor never parking, `arm` blind to harness/kickoff mismatches, and timeout wake text misdirecting dependency parks.

**Architecture:** One new `supervise` subcommand in `sprint-mail.sh` (idempotent arm wrapper for codex/claude; CronCreate payload printer for kimi), a warn-only harness detector in `arm`, and a glob-branched timeout message in the two Stop hooks. SKILL.md prose slims to point at `supervise`.

**Tech Stack:** bash 3.2 (macOS system bash — no flock, no associative arrays), bash+grep tests only, repo lint (`test/lint-skills.sh`).

## Global Constraints

- Spec: `docs/superpowers/specs/2026-07-20-supervisor-sweep-enforcement-design.md` (commits `8e2c820` + `6214013`). Every requirement below traces to it.
- **Edits are live deploys** — installed skills are symlinks into this repo (repo `AGENTS.md`).
- **bash 3.2 dialect**, macOS tools: `stat -f %m`, `ps -o command= -p`, `cksum`. No GNU-isms.
- The two Stop-hook bodies (from `set -u` onward) must stay **byte-identical** — enforced by a lint diff pin (`test/lint-skills.sh:311-314`). Edit both files with identical content.
- **Lint moves with prose**: any changed pinned string is updated in `test/lint-skills.sh` in the same commit (repo `AGENTS.md` — "a passing lint that no longer checks the real string is worse than no lint").
- Existing lint pins that MUST survive in `sprint-orchestrator/SKILL.md`: `'*-question.md *-concluded.md'`, `arm --harness codex <sprint-dir> '*-question.md *-concluded.md' 1800`, `arm --harness claude <sprint-dir> '*-question.md *-concluded.md' 10800`, `recurring cron`, `the supervisor is always a main session`, `sprint-mail.sh unread`, `nor the read-cursor`.
- Tests are hermetic: `SPRINT_MAIL_ROOT=$(mktemp -d)` fixtures, `SPRINT_MAIL_POLL=1`, wired fake `CODEX_HOME`/`CLAUDE_CONFIG_DIR` (see `test-sprint-mail.sh:103-144`).
- Wait record format (unchanged): four lines — worktree root, absolute glob(s), timeout, absolute cursor path.

---

### Task 1: arm harness-mismatch warning

**Files:**
- Modify: `sprint-orchestrator/sprint-mail.sh` (header comment; new `detect_harness`; warning inside `arm`)
- Test: `sprint-orchestrator/test/test-sprint-mail.sh`

**Interfaces:**
- Consumes: existing `arm` code path (`sprint-mail.sh:164-206`), existing `err()`.
- Produces: `detect_harness()` — prints `codex`/`claude`/`kimi` on stdout when confidently detected, empty otherwise. `SPRINT_MAIL_ASSUME_HARNESS` env override: `codex|claude|kimi` forces that value, `none` forces empty. Later tasks rely on the override for deterministic tests.

- [ ] **Step 1: Write the failing tests**

Append to `sprint-orchestrator/test/test-sprint-mail.sh`, right after the kimi-refusal block (after line 157, before the path-shaped-pattern checks):

```bash
# ---- arm mismatch warning: SPRINT_MAIL_ASSUME_HARNESS drives detection ----
out="$(SPRINT_MAIL_ASSUME_HARNESS=kimi "$SUT" arm --harness codex "$SPRINT" "07-020-reply.md" 900 2>&1)"; rc=$?
[ "$rc" = "0" ] && case "$out" in *"warning: arming --harness codex"*"looks like kimi"*) true ;; *) false ;; esac \
  && ok "mismatch warns on stderr and still arms" || no "mismatch warns on stderr and still arms (rc=$rc out=$out)"
"$SUT" disarm "$SPRINT"

out="$(SPRINT_MAIL_ASSUME_HARNESS=codex "$SUT" arm --harness codex "$SPRINT" "07-020-reply.md" 900 2>&1)"
case "$out" in *"warning:"*) no "matching harness stays silent" ;; *) ok "matching harness stays silent" ;; esac
"$SUT" disarm "$SPRINT"

out="$(SPRINT_MAIL_ASSUME_HARNESS=none "$SUT" arm --harness codex "$SPRINT" "07-020-reply.md" 900 2>&1)"
case "$out" in *"warning:"*) no "no detection stays silent" ;; *) ok "no detection stays silent" ;; esac
"$SUT" disarm "$SPRINT"
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bash sprint-orchestrator/test/test-sprint-mail.sh 2>&1 | tail -15`
Expected: three FAIL lines — "mismatch warns on stderr and still arms", "matching harness stays silent" currently FAILs only if a warning exists (it won't — this one passes immediately, that is fine), "no detection stays silent" likewise passes immediately. The first MUST fail (no warning implemented yet). The suite's pass/fail summary at the end shows FAIL ≥ 1.

- [ ] **Step 3: Implement `detect_harness` and the warning**

In `sprint-orchestrator/sprint-mail.sh`, add to the header comment block (after the `arm` paragraph, lines 22-29):

```bash
# `arm` also warns (never refuses) when the session it runs in looks like a
# different harness than --harness names — detection walks the ancestor chain's
# full command lines, nearest harness ancestor wins. SPRINT_MAIL_ASSUME_HARNESS
# (codex|claude|kimi|none) overrides detection; it exists for tests.
```

Add the function right after `cursor_file()` (after line 100):

```bash
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
```

Inside the `arm)` case, immediately after the hook-reference `case "$harness" in … esac` verification block (after line 184) and before `echo "$timeout" | grep …`:

```bash
    detected="$(detect_harness)"
    if [ -n "$detected" ] && [ "$detected" != "$harness" ]; then
      echo "sprint-mail: warning: arming --harness $harness but the nearest harness ancestor looks like $detected — the wait record is harness-agnostic and will still fire; check the kickoff's harness matches this session" >&2
    fi
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bash sprint-orchestrator/test/test-sprint-mail.sh`
Expected: all three new tests PASS; whole suite green (no regressions — the warning does not fire in any pre-existing test because none sets `SPRINT_MAIL_ASSUME_HARNESS` and detection in a plain test shell finds nothing to warn about; if the suite IS run from a kimi/codex/claude session, pre-existing arm tests now emit a warning on stderr — that is expected and harmless, they assert on stdout/exit codes).

- [ ] **Step 5: Commit**

```bash
git add sprint-orchestrator/sprint-mail.sh sprint-orchestrator/test/test-sprint-mail.sh
git commit -m "feat(sprint-mail): warn when arm's --harness mismatches the session's harness

Warn-only detection walks the ancestor chain's full command lines,
nearest harness ancestor wins (codex exec under kimi-code is codex).
SPRINT_MAIL_ASSUME_HARNESS overrides detection for tests. The record
stays harness-agnostic — 04a's Claude-kickoff-in-Codex accident proved
refusal would be wrong."
```

---

### Task 2: `supervise` subcommand

**Files:**
- Modify: `sprint-orchestrator/sprint-mail.sh` (usage text, `--harness` pre-parse, new `supervise)` case)
- Test: `sprint-orchestrator/test/test-sprint-mail.sh`

**Interfaces:**
- Consumes: `detect_harness` indirectly via delegation to `arm` (Task 1); existing `arm` record format and `prune_stale`.
- Produces: `sprint-mail.sh supervise --harness <codex|claude|kimi> <sprint-dir>`. For codex/claude: prints the armed record path (via `arm`) or `already armed: <path>`. For kimi: prints the CronCreate payload on stdout, creates no record. Task 4's prose and lint pins reference this exact command spelling.

- [ ] **Step 1: Write the failing tests**

Append to `sprint-orchestrator/test/test-sprint-mail.sh` at the end of the file:

```bash
# ---- supervise: kimi prints the cron park, arms nothing ----
out="$(SPRINT_MAIL_ASSUME_HARNESS=none "$SUT" supervise --harness kimi "$SPRINT" 2>&1)"; rc=$?
[ "$rc" = "0" ] && ok "supervise kimi exits 0" || no "supervise kimi exits 0 (rc=$rc)"
case "$out" in *"docs/sprints/2026-07-14-fixture-sprint"*) ok "kimi payload carries the resolved sprint dir" ;; *) no "kimi payload carries the resolved sprint dir (got: $out)" ;; esac
case "$out" in *"CronList"*"CronCreate"*) ok "kimi payload orders CronList before CronCreate" ;; *) no "kimi payload orders CronList before CronCreate" ;; esac
case "$out" in *"ending the turn is the park"*) ok "kimi payload carries the goal-less fallback" ;; *) no "kimi payload carries the goal-less fallback" ;; esac
case "$out" in *"CronDelete"*) ok "kimi payload names CronDelete on conclusion" ;; *) no "kimi payload names CronDelete on conclusion" ;; esac
[ -z "$(ls "$WAITS"/wait-* 2>/dev/null)" ] \
  && ok "supervise kimi arms no wait record" || no "supervise kimi arms no wait record"

# ---- supervise: codex arms the sweep wait idempotently ----
SPRINT_MAIL_ASSUME_HARNESS=none "$SUT" supervise --harness codex "$SPRINT" >/dev/null
rec_s="$(ls "$WAITS"/wait-* 2>/dev/null | head -1)"
[ -n "$rec_s" ] && [ "$(sed -n 2p "$rec_s")" = "$MDIR/*-question.md $MDIR/*-concluded.md" ] \
  && ok "supervise codex arms the supervisor sweep glob" || no "supervise codex arms the supervisor sweep glob (got: $(sed -n 2p "$rec_s" 2>/dev/null))"
[ "$(sed -n 3p "$rec_s")" = "1800" ] && ok "supervise codex budget is 1800" || no "supervise codex budget is 1800"
out="$(SPRINT_MAIL_ASSUME_HARNESS=none "$SUT" supervise --harness codex "$SPRINT" 2>&1)"; rc=$?
[ "$rc" = "0" ] && case "$out" in *"already armed"*) true ;; *) false ;; esac \
  && ok "supervise re-run is idempotent on glob match" || no "supervise re-run is idempotent on glob match (rc=$rc out=$out)"
[ "$(ls "$WAITS"/wait-* | wc -l | tr -d ' ')" = "1" ] \
  && ok "still exactly one record" || no "still exactly one record"
"$SUT" disarm "$SPRINT"
"$SUT" arm --harness codex "$SPRINT" "07-030-reply.md" 900 >/dev/null
out="$(SPRINT_MAIL_ASSUME_HARNESS=none "$SUT" supervise --harness codex "$SPRINT" 2>&1)"; rc=$?
[ "$rc" = "2" ] && case "$out" in *"already armed"*"disarm"*) true ;; *) false ;; esac \
  && ok "supervise refuses behind a different wait" || no "supervise refuses behind a different wait (rc=$rc out=$out)"
"$SUT" disarm "$SPRINT"

# ---- supervise: claude budget is 10800 ----
SPRINT_MAIL_ASSUME_HARNESS=none "$SUT" supervise --harness claude "$SPRINT" >/dev/null
rec_c="$(ls "$WAITS"/wait-* 2>/dev/null | head -1)"
[ "$(sed -n 3p "$rec_c")" = "10800" ] && ok "supervise claude budget is 10800" || no "supervise claude budget is 10800"
"$SUT" disarm "$SPRINT"
```

Note: `$WAITS` and `$MDIR` are already defined earlier in the test file (lines 110 and the fixture setup); `$CLAUDE_CONFIG_DIR` was wired at line 133-135 and `$CODEX_HOME` at 103/144, so both harness verifications pass.

- [ ] **Step 2: Run tests to verify they fail**

Run: `bash sprint-orchestrator/test/test-sprint-mail.sh 2>&1 | tail -20`
Expected: FAILs — "supervise kimi exits 0" fails first (unknown subcommand → usage, exit 2).

- [ ] **Step 3: Implement `supervise`**

**3a.** Update both usage blocks in `sprint-orchestrator/sprint-mail.sh` — the header comment (after line 7) and the `usage()` heredoc (after line 45) each gain:

```
       sprint-mail.sh supervise --harness <codex|claude|kimi> <sprint-dir>
```

(Header comment uses the same line without leading `usage:` alignment concerns — match the existing 7-space indent in `usage()`, and in the header block add it as `   sprint-mail.sh supervise --harness <codex|claude|kimi> <sprint-dir>`.)

**3b.** Replace the `--harness` pre-parse block (lines 55-68) with:

```bash
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
```

Note: the old code let a bare `arm` fall through to fail differently; the existing test at line 146-149 asserts a bare `arm` is refused naming `--harness` — the new `err` text contains `--harness`, so it still passes.

**3c.** Add the `supervise)` case inside the big `case "$cmd" in` (place it after the `arm)` case ends, before `disarm)`):

```bash
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
```

The `exec "$0" arm …` delegation reuses arm's hook-reference verification, `prune_stale`, and record writing; supervise's own loop above guarantees no conflicting record exists, so arm's double-arm check passes.

- [ ] **Step 4: Run tests to verify they pass**

Run: `bash sprint-orchestrator/test/test-sprint-mail.sh`
Expected: all new supervise tests PASS, whole suite green.

- [ ] **Step 5: Commit**

```bash
git add sprint-orchestrator/sprint-mail.sh sprint-orchestrator/test/test-sprint-mail.sh
git commit -m "feat(sprint-mail): supervise subcommand — one park command per harness

codex/claude: idempotent arm of the supervisor sweep glob (1800/10800),
idempotency matched on the armed record's glob — a different wait still
fails loudly. kimi: prints the exact CronCreate sweep payload (CronList
before CronCreate, goal-blocked or goal-less park, CronDelete on
conclusion) and arms nothing. Closes the goal-less Kimi supervisor park
hole from the 2026-07-20-remediation-sprint-1 post-mortem."
```

---

### Task 3: Timeout wake text branches on the armed glob

**Files:**
- Modify: `sprint-orchestrator/codex-stop-wait.sh` (timeout `else` branch)
- Modify: `sprint-orchestrator/claude-stop-wait.sh` (identical edit — bodies byte-identical by lint pin)
- Test: `sprint-orchestrator/test/test-codex-stop-wait.sh`
- Test: `sprint-orchestrator/test/test-claude-stop-wait.sh`

**Interfaces:**
- Consumes: the wait record's line 2 (`$glob`), already read at `codex-stop-wait.sh:46`.
- Produces: three timeout message branches + strict fallback, selected by `case "$glob" in`. The supervisor-branch text names `sprint-mail.sh supervise` (Task 2's command), reinforcing the new park path.

- [ ] **Step 1: Write the failing tests**

Append to **both** `sprint-orchestrator/test/test-codex-stop-wait.sh` and `sprint-orchestrator/test/test-claude-stop-wait.sh` (identical blocks; each file's `arm` helper writes a single legacy record at `$WAITS/wait-t`, overwriting the previous):

```bash
# ---- timeout text branches on the armed glob ----
arm "$MDIR/07-*-note.md" 2 0
out="$(: | "$SUT" 2>&1)"
case "$out" in *"dependency park"*"keep parking"*) ok "note-only glob → park timeout text" ;; *) no "note-only glob → park timeout text (got: $out)" ;; esac

arm "$MDIR/07-*-reply.md $MDIR/07-*-note.md" 2 0
out="$(: | "$SUT" 2>&1)"
case "$out" in *"no-reply fallback"*) ok "combined glob → reply text wins" ;; *) no "combined glob → reply text wins (got: $out)" ;; esac

arm "$MDIR/*-question.md $MDIR/*-concluded.md" 2 0
out="$(: | "$SUT" 2>&1)"
case "$out" in *"Supervisors: sweep ALL new mail"*"supervise"*) ok "supervisor glob → sweep/re-arm text" ;; *) no "supervisor glob → sweep/re-arm text (got: $out)" ;; esac

arm "$MDIR/misc-file.txt" 2 0
out="$(: | "$SUT" 2>&1)"
case "$out" in *"no-reply fallback"*) ok "unmatched glob → strict fallback text" ;; *) no "unmatched glob → strict fallback text (got: $out)" ;; esac
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bash sprint-orchestrator/test/test-codex-stop-wait.sh 2>&1 | tail -8`
Expected: FAILs on "note-only glob → park timeout text" and "supervisor glob → sweep/re-arm text" (today's single message contains neither "dependency park" nor the supervise naming). "combined glob" and "unmatched glob" pass immediately — correct, they pin the fallback behavior.

- [ ] **Step 3: Implement the branch in both hooks**

In `sprint-orchestrator/codex-stop-wait.sh`, replace the `else` branch of the final `if [ -n "$found" ]` (lines 77-79) with:

```bash
else
  case "$glob" in
    *-reply.md*)
      # question-wait (also wins for combined reply+note records: the reply is
      # the blocking need, the note match is opportunistic)
      echo "Armed mailbox wait timed out after ${timeout}s with no new mail. Executors: take the contract's no-reply fallback (handback/blocked) and post your terminal concluded. Supervisors: sweep, then re-arm if the wave is still running." >&2 ;;
    *-note.md*)
      # dependency park — expiring is not a verdict on the gate
      echo "Armed mailbox wait timed out after ${timeout}s with no new mail. This was a dependency park on a gate note — the gate is still closed. Re-arm the same wait and keep parking; do NOT post a terminal concluded merely because the wait expired. Take the handback path only if the dependency's premise changed." >&2 ;;
    *-question.md*|*-concluded.md*)
      # supervisor sweep form
      echo "Armed mailbox wait timed out after ${timeout}s with no new mail. Supervisors: sweep ALL new mail with sprint-mail.sh unread, then re-arm (sprint-mail.sh supervise) before ending the turn if the wave is still running." >&2 ;;
    *)
      # unknown pattern — strict fallback, today's behavior
      echo "Armed mailbox wait timed out after ${timeout}s with no new mail. Executors: take the contract's no-reply fallback (handback/blocked) and post your terminal concluded. Supervisors: sweep, then re-arm if the wave is still running." >&2 ;;
  esac
fi
```

Apply the **byte-identical** edit to `sprint-orchestrator/claude-stop-wait.sh` (same lines — the files' bodies from `set -u` onward must stay identical; verify with `diff <(sed -n '/^set -u$/,$p' sprint-orchestrator/codex-stop-wait.sh) <(sed -n '/^set -u$/,$p' sprint-orchestrator/claude-stop-wait.sh)` and expect no output).

- [ ] **Step 4: Run tests to verify they pass**

Run: `bash sprint-orchestrator/test/test-codex-stop-wait.sh && bash sprint-orchestrator/test/test-claude-stop-wait.sh`
Expected: both suites green, including all four new branch tests in each.

- [ ] **Step 5: Commit**

```bash
git add sprint-orchestrator/codex-stop-wait.sh sprint-orchestrator/claude-stop-wait.sh sprint-orchestrator/test/test-codex-stop-wait.sh sprint-orchestrator/test/test-claude-stop-wait.sh
git commit -m "feat(stop-hooks): branch timeout wake text on the armed glob

reply globs (and combined reply+note records) keep the strict no-reply
fallback; note-only globs get dependency-park text (re-arm and keep
parking, never a terminal concluded on expiry); supervisor sweep globs
get the sweep-and-re-arm text naming sprint-mail.sh supervise. Hook
bodies remain byte-identical."
```

---

### Task 4: SKILL.md prose + lint pins

**Files:**
- Modify: `sprint-orchestrator/SKILL.md:215-236` (Supervising section's wait paragraph)
- Modify: `test/lint-skills.sh` (pins move with prose)

**Interfaces:**
- Consumes: Task 2's exact command spelling (`sprint-mail.sh supervise --harness`), Task 3's supervisor-branch behavior.
- Produces: the prose every future supervisor reads. New lint pins: `sprint-mail.sh supervise --harness`, `ending the turn is the park`, `CronList first` in `$ORCH`.

- [ ] **Step 1: Rewrite the Supervising-section wait paragraph**

In `sprint-orchestrator/SKILL.md`, replace the text from "Then re-arm as an idle nudge and end the turn" (line 215) through "a missed wake is caught by the next sweep." (line 236) with the following. The cursor-sweep sentences before it (lines 211-215, up to "…the next turn catches it.") and the sentences after it ("Answer executor `question`s…" line 237) stay untouched:

```markdown
Then park the turn with ONE command — `sprint-mail.sh supervise --harness <your harness>
<sprint-dir>` — and follow its output. The supervisor is always a main session, so each harness
waits in its own way: for Codex and Claude, supervise idempotently arms the sweep wait
(`arm --harness codex <sprint-dir> '*-question.md *-concluded.md' 1800`;
`arm --harness claude <sprint-dir> '*-question.md *-concluded.md' 10800` — the idle-wait default
under the installed hook's 10860s timeout; targeted reply waits keep 1800) and the Stop hook
wakes you on new mail or timeout. On Kimi there is no Stop hook to arm — the wait is a recurring
cron sweep, and supervise prints the exact task: CronList first, CronCreate only if no sweep
task exists, then end the turn — with an active goal, mark it blocked (the blocked state IS the
park: an active goal's continuation turns starve cron delivery, fires land only at idle); with
no active goal, simply ending the turn is the park. The recurring task replaces the arm/re-arm
loop — one task per wave, not one per wake; CronDelete it when the wave concludes. The Kimi
session must run with a permission posture that lets the mailbox commands and cron management
execute unattended (an auto permission mode or session-approved allow rules) — a sweep that
stalls on an approval panel wakes no one. Re-arm on each wake until the wave concludes — a
spurious wake finds nothing unread, a missed wake is caught by the next sweep.
```

Check every surviving pinned string from Global Constraints is still present verbatim in the file (grep for each).

- [ ] **Step 2: Update the lint**

In `test/lint-skills.sh`, after line 95 (the claude re-arm pin), add:

```bash
has   "orchestrator: supervisor parks via supervise" "sprint-mail.sh supervise --harness" "$ORCH"
has   "orchestrator: kimi park has goal-less fallback" "ending the turn is the park" "$ORCH"
has   "orchestrator: kimi sweep creates only if absent" "CronList first" "$ORCH"
```

Also add a pin for the script's usage text. Find the existing sprint-mail.sh pins section (search for `sprint-mail.sh` variable assignments in lint-skills.sh, e.g. near the `$CSW`/`$CLSW` hook pins around line 300) and add, using the same `has` helper and the file's existing variable for sprint-mail.sh (create `SMAIL="$HERE/../sprint-orchestrator/sprint-mail.sh"` next to the hook variables if none exists):

```bash
has   "sprint-mail: usage names supervise"        "sprint-mail.sh supervise --harness <codex|claude|kimi> <sprint-dir>" "$SMAIL"
has   "sprint-mail: kimi payload goal-less park"  "ending the turn is the park" "$SMAIL"
```

- [ ] **Step 3: Run the full verification**

Run:
```bash
test/lint-skills.sh
bash sprint-orchestrator/test/test-sprint-mail.sh
bash sprint-orchestrator/test/test-codex-stop-wait.sh
bash sprint-orchestrator/test/test-claude-stop-wait.sh
bash sprint-orchestrator/test/test-sprint-status.sh
bash sprint-orchestrator/test/test-wave-handoffs.sh
codex/test/test.sh
```
Expected: all green. The lint must show the three new pins passing and zero FAILs overall.

- [ ] **Step 4: Commit**

```bash
git add sprint-orchestrator/SKILL.md test/lint-skills.sh
git commit -m "docs(sprint-orchestrator): supervisor parks via sprint-mail.sh supervise

The Supervising section's per-harness arm sentences collapse to one
command whose output is harness-resolved; the kimi cron park becomes a
printed payload instead of prose to remember. Lint pins the new command
spelling and the goal-less fallback wording; the arm-form pins survive
as the reference line."
```

---

## Self-Review Results

**Spec coverage:** §1 → Task 2 (+ Task 4 prose); §2 → Task 1; §3 → Task 3. Spec "Files touched" matches plan files exactly. Spec "Tests" items 1-4 map to Tasks 2, 2, 1, 3 respectively — including the Codex-gate amendments (glob-matched idempotency in Task 2's "refuses behind a different wait" test; CronList-before-CronCreate ordering assertion; combined-glob precedence in Task 3's "combined glob" test; nearest-ancestor/full-command-line detection in Task 1's `detect_harness`).

**Placeholder scan:** none — every code step carries complete code.

**Type/name consistency:** `detect_harness`, `SPRINT_MAIL_ASSUME_HARNESS` (values `codex|claude|kimi|none`), `supervise --harness <codex|claude|kimi>`, sweep glob `'*-question.md *-concluded.md'`, budgets 1800/10800 — identical across tasks, tests, prose, and lint pins. The supervisor timeout text in Task 3 names `sprint-mail.sh supervise`, which Task 2 creates and Task 4's prose prescribes — consistent.

---

## Corrections applied during execution

The plan text above is as-written; the landed code differs in these places
(each verified by its task reviewer; commits in parentheses):

1. **Task 1, detect_harness** (9e0b8db, e933844): the per-command-line match is
   factored into a pure `classify_cmd()` that `detect_harness` calls (makes the
   shipped code unit-testable via sed-extraction). argv[0] basename is derived
   in-shell (`${cmd%% *}` + `${base##*/}`) — the plan's `basename "$(awk …)"`
   invocation hits macOS `basename` option-parsing on login-shell argv[0]
   (`-zsh`). Match list extended: `kimi-code` → kimi (the Kimi CLI's real
   process name), `Codex*` basename and `Codex Framework` paths → codex
   (Codex.app helpers present as `Codex (Renderer)`/`Codex (Service)`).
   `SPRINT_MAIL_ASSUME_HARNESS` also accepts `none` (forces no detection; the
   deterministic silence path in tests).
2. **Task 2, Step 1** (8493f9b): the supervise test block is inserted
   immediately BEFORE the pass/fail summary in `test-sprint-mail.sh`, not
   "at the end of the file" — appending after the summary would leave the new
   tests uncounted.
3. **Task 3, Step 1** (6877549): the supervisor-glob timeout test needs one
   setup line before its arm, identical in both hook test files:
   `rm -f "$MDIR"/*-question.md "$MDIR"/*-concluded.md` — earlier tests leave
   question fixtures in `$MDIR` that would wake the legacy wait instead of
   timing it out.
4. **Task 4, Step 1 prose** (a1950cf): two forced, word-preserving reflows —
   ". The supervisor" became "— the supervisor" (the lint pin greps the
   lowercase string), and the `recurring cron` line was reflowed so the pin's
   two words sit on one line.
5. **Task 2, supervise idempotency** (final whole-branch review): supervise's
   codex|claude path now runs `prune_stale "$waits_dir"` before the glob-match
   loop, matching arm's ordering — the plan's `supervise)` case omitted it, so
   a sweep record whose hook never fired (older than 2× its timeout, identity
   dir alive — the dead-park signature) would have been ratified
   "already armed" forever.
