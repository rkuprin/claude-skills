# Mailbox read-cursor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give `sprint-mail.sh` a durable per-consumer read-cursor (`unread`/`seen`) and rewrite the orchestrator and executor mailbox prose to sweep it first, so mail is exact to detect and never lost while an agent is taking steps.

**Architecture:** Two new coreutils-only subcommands on the existing `sprint-mail.sh`. A cursor file lives at `<mail_dir>/.read/<key>` (key = `cksum` of `pwd -P`), holding one consumed mail basename per line. `unread` prints matching mail minus the cursor; `seen` appends to it. The Codex Stop hook and the `arm`/`disarm`/`wait`/`since`-epoch surface are untouched — the cursor becomes the source of truth for *what to read*, the hook stays a best-effort wake. Prose changes make a cursor sweep the first action of every turn/step.

**Tech Stack:** Bash 3.2, coreutils only (`ls`, `grep`, `cksum`, `basename`, `mkdir`). Tests and lint are bash + `grep` only — no YAML parser, no other runtime.

## Global Constraints

- **Bash 3.2, no `flock`, coreutils only.** No `jq`, no GNU-only flags. `stat`/`cksum`/`ls`/`grep`/`basename` only.
- **Each cursor has a single writer** (one consumer cwd), so plain `>>` appends are race-free — no locking.
- **The read-cursor is never sprint state.** `sprint-status.sh` never reads it; deleting it loses nothing (worst case: a consumer re-reads already-seen mail once). Story state stays git-derived.
- **`.read/` must stay invisible to `list`.** `ls` without `-a` omits the dot-directory, and `list`'s `^NN-[0-9]{3}-` filter would drop it anyway — do not break either.
- **Prose is the product; lint pins it.** When you change pinned prose, update `test/lint-skills.sh` in the **same commit**. A passing lint that no longer checks the real string is worse than none.
- **Never write `git checkout main` as an instruction** in any agent-handoff file (lint rejects un-negated occurrences).
- **Surgical scope.** Touch only `sprint-orchestrator/sprint-mail.sh`, `sprint-orchestrator/test/test-sprint-mail.sh`, `sprint-orchestrator/SKILL.md`, `agent-handoff/EXECUTION.md`, `test/lint-skills.sh`. Do **not** touch the Stop hook, `arm`/`disarm`/`wait`, `install-codex-hook.sh`, or any README.
- **Every commit** ends with the standard `Co-Authored-By:` and `Claude-Session:` trailers per the harness rule.
- **Edits are live** (skills are symlinks into this repo); treat every edit as a deploy.

---

### Task 1: `unread` and `seen` subcommands in `sprint-mail.sh`

**Files:**
- Modify: `sprint-orchestrator/sprint-mail.sh` (header comment ~lines 1–23; `usage()` ~lines 29–38; add two `case` arms before the final `*) usage ;;` at ~line 153)
- Test: `sprint-orchestrator/test/test-sprint-mail.sh` (append a cursor block before the final `printf '\n%d passed...'` at line 142)
- Modify: `test/lint-skills.sh` (add two SMAIL pins after line 257)

**Interfaces:**
- Produces: `sprint-mail.sh unread <sprint-dir> <name-or-glob(s)>` → prints matching mail (mtime order, oldest first) whose basename is not in this cwd's cursor; exit 0 with no output when all are seen or the mail dir is absent.
- Produces: `sprint-mail.sh seen <sprint-dir> <file>...` → appends each file's basename to this cwd's cursor (idempotent), creating `<mail_dir>/.read/` on first use.
- Cursor path: `<mail_dir>/.read/<key>` where `key="$(pwd -P | cksum | cut -d' ' -f1)"` and `mail_dir="$MAIL_ROOT/$repo/$(basename "$sprint_dir")"` (already computed at the top of the script).

- [ ] **Step 1: Write the failing tests**

Append this block to `sprint-orchestrator/test/test-sprint-mail.sh` immediately **before** the final two lines (`printf '\n%d passed, %d failed\n' ...` and `[ "$FAIL" -eq 0 ]`):

```bash
# ---- unread/seen: durable per-consumer read-cursor ----
cd "$REPO_A"
SPRINT2="docs/sprints/2026-07-19-cursor-fixture"
MDIR2="$SPRINT_MAIL_ROOT/repo-alpha/2026-07-19-cursor-fixture"
q1="$(printf 'q\n'  | "$SUT" post "$SPRINT2" 05 question -)"           # 05-001-question.md
e1="$(printf 'e\n'  | "$SUT" post "$SPRINT2" 05 evidence -)"           # 05-002-evidence.md
c1="$(printf 'outcome: pr-ready\nPR\n' | "$SUT" post "$SPRINT2" 05 concluded -)"  # 05-003-concluded.md

# all three unseen, mtime order oldest-first
u_all="$("$SUT" unread "$SPRINT2" '*')"
[ "$(printf '%s\n' "$u_all" | grep -c .)" = "3" ] && ok "unread returns all unseen mail" || no "unread returns all unseen mail (got: $u_all)"
[ "$(printf '%s\n' "$u_all" | head -1)" = "$q1" ] && ok "unread is mtime-ordered oldest-first" || no "unread is mtime-ordered oldest-first (got head: $(printf '%s\n' "$u_all" | head -1))"

# seen excludes
"$SUT" seen "$SPRINT2" "$q1" "$e1"
u2="$("$SUT" unread "$SPRINT2" '*')"
[ "$u2" = "$c1" ] && ok "seen files excluded from unread" || no "seen files excluded from unread (got: $u2)"

# two-glob stale-match guard: with c1 also seen, a blocking-kind sweep is empty
# until a genuinely new question lands (the old two-glob `wait` false-fired on stale c1)
"$SUT" seen "$SPRINT2" "$c1"
u_block="$("$SUT" unread "$SPRINT2" '*-question.md *-concluded.md')"
[ -z "$u_block" ] && ok "two-glob unread does not false-fire on stale seen mail" || no "two-glob unread false-fired (got: $u_block)"
q2="$(printf 'q2\n' | "$SUT" post "$SPRINT2" 05 question -)"           # 05-004-question.md
u_block2="$("$SUT" unread "$SPRINT2" '*-question.md *-concluded.md')"
[ "$u_block2" = "$q2" ] && ok "two-glob unread surfaces the genuinely new question" || no "two-glob unread new question (got: $u_block2)"

# multiple explicit globs, both already seen → empty
u_multi="$("$SUT" unread "$SPRINT2" '05-001-question.md 05-002-evidence.md')"
[ -z "$u_multi" ] && ok "unread accepts multiple globs" || no "unread multiple globs (got: $u_multi)"

# seen is idempotent — no duplicate cursor lines
"$SUT" seen "$SPRINT2" "$q1"; "$SUT" seen "$SPRINT2" "$q1"
dupes="$(cat "$MDIR2/.read/"* 2>/dev/null | grep -c '^05-001-question.md$')"
[ "$dupes" = "1" ] && ok "seen is idempotent" || no "seen is idempotent (got: $dupes)"

# .read/ invisible to list
"$SUT" list "$SPRINT2" | grep -q '\.read' && no ".read cursor hidden from list" || ok ".read cursor hidden from list"

# seen created .read/ and a cursor file
[ -d "$MDIR2/.read" ] && ls "$MDIR2/.read/"* >/dev/null 2>&1 && ok "seen creates .read/ and a cursor file" || no "seen creates .read/ and a cursor file"

# cursor is per-cwd: same mailbox, a different cwd still sees q2 unread
"$SUT" seen "$SPRINT2" "$q2"
mkdir -p "$REPO_A/deep/sub"; cd "$REPO_A/deep/sub"
u_sub="$("$SUT" unread "$SPRINT2" '05-004-question.md')"
[ "$u_sub" = "$q2" ] && ok "cursor is per-cwd (other cwd still sees q2 unread)" || no "cursor is per-cwd (got: $u_sub)"
cd "$REPO_A"

# cursor is per-sprint: it lives inside each sprint's mail dir
SPRINT3="docs/sprints/2026-07-19-cursor-fixture-b"
q3="$(printf 'q\n' | "$SUT" post "$SPRINT3" 05 question -)"
u3="$("$SUT" unread "$SPRINT3" '*')"
[ "$u3" = "$q3" ] && ok "cursor is per-sprint (SPRINT2 marks don't leak)" || no "cursor is per-sprint (got: $u3)"
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `sprint-orchestrator/test/test-sprint-mail.sh`
Expected: FAIL — the new `unread`/`seen` cases fail because those subcommands hit the `*) usage ;;` arm (exit 2), so `ok` is never reached. The final line reports a non-zero failed count and the script exits 1.

- [ ] **Step 3: Add the cursor helper and the two subcommands**

In `sprint-orchestrator/sprint-mail.sh`, add a `cursor_file` helper next to `next_seq` (after line 59, before `case "$cmd" in`):

```bash
cursor_file() {  # per-consumer read-cursor path, keyed by canonical cwd
  # Lives inside the mail dir, so it is namespaced per sprint and disposed with
  # the mailbox. cksum of the cwd is a stable, coreutils-portable, fixed-length
  # key; a collision among a handful of absolute paths is astronomically
  # unlikely and the cursor is transient — never sprint state.
  printf '%s\n' "$mail_dir/.read/$(pwd -P | cksum | cut -d' ' -f1)"
}
```

Then add these two arms to the `case "$cmd" in` switch, immediately before the final `*) usage ;;` line:

```bash
  unread)
    pat="${3:-}"
    [ -n "$pat" ] || usage
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
    mkdir -p "$mail_dir/.read"
    cur="$(cursor_file)"
    for f in "$@"; do
      bn="$(basename "$f")"
      grep -qxF "$bn" "$cur" 2>/dev/null || printf '%s\n' "$bn" >> "$cur"
    done
    ;;
```

Add two lines to the `usage()` heredoc (after the `disarm` line):

```
       sprint-mail.sh unread <sprint-dir> <name-or-glob(s)>
       sprint-mail.sh seen <sprint-dir> <file>...
```

Add to the top-of-file usage comment block (after the `disarm` synopsis at ~line 8):

```
#   sprint-mail.sh unread <sprint-dir> <name-or-glob(s)>
#   sprint-mail.sh seen <sprint-dir> <file>...
```

And add a short note near the `arm` documentation paragraph (after line 23):

```
# `unread`/`seen` are a durable per-consumer read-cursor: `unread` lists mail
# matching the glob(s) minus this cwd's cursor; `seen` appends read basenames.
# The cursor lives at <mail_dir>/.read/<cksum of cwd>, is namespaced per sprint,
# and is NEVER state — sprint-status.sh never reads it, deleting it loses nothing.
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `sprint-orchestrator/test/test-sprint-mail.sh`
Expected: PASS — final line `N passed, 0 failed`, exit 0. All prior cases (post/list/wait/arm/disarm) still pass unchanged.

- [ ] **Step 5: Add the lint pins for the new usage lines**

In `test/lint-skills.sh`, after line 257 (`"mail: arm refuses without wired hook"`), add:

```bash
has   "mail: unread usage line"                 "unread <sprint-dir> <name-or-glob(s)>" "$SMAIL"
has   "mail: seen usage line"                   "seen <sprint-dir> <file>..." "$SMAIL"
```

- [ ] **Step 6: Run the lint to verify it passes**

Run: `test/lint-skills.sh`
Expected: PASS — the two new pins are green, every existing pin still green (nothing else changed yet; the epoch-dance pin at line 94 is untouched here and its string still exists in `SKILL.md`).

- [ ] **Step 7: Commit**

```bash
git add sprint-orchestrator/sprint-mail.sh sprint-orchestrator/test/test-sprint-mail.sh test/lint-skills.sh
git commit -m "feat(sprint): add read-cursor unread/seen to sprint-mail"
# (append the standard Co-Authored-By / Claude-Session trailers)
```

---

### Task 2: Orchestrator sweeps the cursor first (prose + lint flip)

**Files:**
- Modify: `sprint-orchestrator/SKILL.md` (the "watch the mailbox reactively" paragraph, lines 202–211)
- Modify: `test/lint-skills.sh` (flip pin at line 94; add three ORCH pins)

**Interfaces:**
- Consumes: `sprint-mail.sh unread`/`seen` from Task 1.
- Produces: orchestrator prose whose first watch action is `sprint-mail.sh unread <sprint-dir> '*-question.md *-concluded.md'`, retaining the pinned strings `watch the mailbox reactively`, `'*-question.md *-concluded.md'`, and `The mailbox is never state`.

- [ ] **Step 1: Update the lint pins first (they will fail against the current prose)**

In `test/lint-skills.sh`, replace the single line 94:

```bash
has   "orchestrator: re-arm after each sweep"   "re-arm with the epoch of that sweep" "$ORCH"
```

with:

```bash
has   "orchestrator: sweep unread first"        "sprint-mail.sh unread" "$ORCH"
hasnt "orchestrator: no epoch dance"            "re-arm with the epoch of that sweep" "$ORCH"
has   "orchestrator: read-cursor never state"   "nor the read-cursor" "$ORCH"
```

- [ ] **Step 2: Run the lint to verify it fails**

Run: `test/lint-skills.sh`
Expected: FAIL — `"orchestrator: sweep unread first"` fails (SKILL.md has no `sprint-mail.sh unread` yet), `"orchestrator: no epoch dance"` fails (the epoch phrase is still present), `"orchestrator: read-cursor never state"` fails.

- [ ] **Step 3: Rewrite the orchestrator watch paragraph**

In `sprint-orchestrator/SKILL.md`, replace lines 202–211 (the paragraph beginning "While the wave runs, watch the mailbox reactively" through "`sprint-status.sh` never reads / the mailbox.") with:

```markdown
While the wave runs, watch the mailbox reactively — never by hand-polling. The first action of
every turn is a cursor sweep: `sprint-mail.sh unread <sprint-dir> '*-question.md *-concluded.md'`
for the blocking kinds, then `sprint-mail.sh unread <sprint-dir> '*'` for the rest — read them,
then `sprint-mail.sh seen <sprint-dir> <files>`. That sweep against the durable read-cursor is
what makes mail never-lost: even if no wake fires, the next turn catches it. Then re-arm as an
idle nudge and end the turn — on Codex with the sprint Stop hook installed:
`sprint-mail.sh arm <sprint-dir> '*-question.md *-concluded.md' 1800`, and the hook wakes you on
new mail or timeout; on Claude: run `sprint-mail.sh wait` as a background task. Re-arm on each
wake until the wave concludes — a spurious wake finds nothing unread, a missed wake is caught by
the next sweep. Answer executor `question`s with the plan's authority; `note` redirects are legal
only while a story has not concluded. The mailbox is never state: DONE is still both trailers on a
trunk-reachable commit, and `sprint-status.sh` never reads the mailbox — nor the read-cursor.
```

- [ ] **Step 4: Run the lint to verify it passes**

Run: `test/lint-skills.sh`
Expected: PASS — the three new pins are green (`sprint-mail.sh unread` present, epoch phrase absent, `nor the read-cursor` present); the retained pins `"orchestrator: reactive mailbox watch"`, `"orchestrator: supervisor arm globs"`, `"orchestrator: mailbox never state"` still green.

- [ ] **Step 5: Confirm the mailbox tests are unaffected**

Run: `sprint-orchestrator/test/test-sprint-mail.sh`
Expected: PASS — `N passed, 0 failed` (prose-only change; behavior unchanged).

- [ ] **Step 6: Commit**

```bash
git add sprint-orchestrator/SKILL.md test/lint-skills.sh
git commit -m "feat(sprint): sweep the read-cursor first in the wave watch"
# (append the standard Co-Authored-By / Claude-Session trailers)
```

---

### Task 3: Executor cursor-aware note sweep (prose + lint)

**Files:**
- Modify: `agent-handoff/EXECUTION.md` (note-check bullet lines 141–142; add cursor clause near the "mailbox is never state" paragraph lines 144–146)
- Modify: `test/lint-skills.sh` (add two AHEXEC pins)

**Interfaces:**
- Consumes: `sprint-mail.sh unread`/`seen` from Task 1.
- Produces: executor prose whose per-step note-check is a cursor sweep, retaining the pinned string `notes before merge or PR`.

- [ ] **Step 1: Add the lint pins first (they will fail against the current prose)**

In `test/lint-skills.sh`, after line 199 (`"contract: notes read before merge"`), add:

```bash
has   "contract: note sweep via unread"      "sprint-mail.sh unread <sprint-dir> '{NN}-*-note.md'" "$AHEXEC"
has   "contract: read-cursor never state"    "nor the read-cursor" "$AHEXEC"
```

- [ ] **Step 2: Run the lint to verify it fails**

Run: `test/lint-skills.sh`
Expected: FAIL — both new pins fail (EXECUTION.md has neither the `unread` note-sweep line nor the `nor the read-cursor` clause yet).

- [ ] **Step 3: Rewrite the executor note-check and add the cursor clause**

In `agent-handoff/EXECUTION.md`, replace lines 141–142:

```markdown
- Check for new `note` messages from the supervisor at each numbered step boundary, and read
  all of your story's notes before merge or PR.
```

with:

```markdown
- Sweep new `note` messages at each numbered step boundary:
  `sprint-mail.sh unread <sprint-dir> '{NN}-*-note.md'`, read them, then
  `sprint-mail.sh seen <sprint-dir> <files>` — the read-cursor means a note is never missed nor
  re-read. Read all of your story's notes before merge or PR.
```

Then, in the "mailbox is never state" paragraph (lines 144–146), change the sentence
`and \`sprint-status.sh\` never reads the mailbox.` to:
`and \`sprint-status.sh\` never reads the mailbox — nor the read-cursor.`

- [ ] **Step 4: Run the lint to verify it passes**

Run: `test/lint-skills.sh`
Expected: PASS — both new AHEXEC pins green; the retained pin `"contract: notes read before merge"` (`notes before merge or PR`) still green.

- [ ] **Step 5: Run the full suite to confirm nothing regressed**

Run each and confirm a passing tail / exit 0:

```bash
test/lint-skills.sh
sprint-orchestrator/test/test-sprint-mail.sh
sprint-orchestrator/test/test-sprint-status.sh
sprint-orchestrator/test/test-wave-handoffs.sh
sprint-orchestrator/test/test-codex-stop-wait.sh
```

Expected: all green — the Stop-hook and `arm`/`wait` suites are untouched by this change and must stay passing.

- [ ] **Step 6: Commit**

```bash
git add agent-handoff/EXECUTION.md test/lint-skills.sh
git commit -m "feat(handoff): cursor-aware note sweep at step boundaries"
# (append the standard Co-Authored-By / Claude-Session trailers)
```

---

## Notes for the executor

- The cursor is transient by design. Tests create fixture sprints under a temp `SPRINT_MAIL_ROOT`; there is nothing to clean up in the real `~/.sprint-mail`.
- If `sprint-mail.sh` fails under `set -euo pipefail` in the `unread` arm, check that every `grep -qxF ... && continue` stays a compound condition (never a bare statement) — a bare failing `grep` would trip `-e`.
- Do **not** "fix" the two-glob `wait` command itself. The spec retires its multi-glob use by moving sweeps to `unread`; the single-file reply `wait` stays exactly as is.
