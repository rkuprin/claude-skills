# Sprint Skill Restructure Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restructure `sprint-orchestrator` and `codex-execution-handoff` into two version-controlled skills whose story state is derived from git rather than stored in filenames, and whose evidence protocol requires screenshots from declared, approved browser drivers.

**Architecture:** Both skills move into the `~/claude-skills` git repo and are symlinked into `~/.claude/skills` and `~/.codex/skills` by the existing `install.sh`. Filesystem state (`.CLAIMED.md`, `done/`) is deleted outright and replaced by a `sprint-status.sh` helper that derives `DONE` from a `Story: NN` commit trailer on trunk, and `DOING` from the existence of a `sprint/NN-*` branch or worktree. `codex-execution-handoff` renders a kickoff prompt for one story; the executing session never invokes it.

**Tech Stack:** Bash (no framework, no new dependencies), Markdown skill files with YAML frontmatter, git plumbing (`git log --grep`, `git show-ref`, `git worktree list`).

## Global Constraints

- Spec of record: `docs/superpowers/specs/2026-07-09-sprint-skill-split-design.md` (revision 2).
- Conventional commits: `type(scope): description`, imperative, under 72 chars, no trailing period.
- Bash only. No new runtime dependencies. Tests are plain bash, matching `codex/test/test.sh`: `ok`/`no` counters, hermetic `mktemp -d` fixtures, never touching the real `~/.codex` or `~/lead-us`.
- The trunk ref is `origin/main`, overridable via the `SPRINT_TRUNK` environment variable so tests can run in a hermetic repo with no remote.
- The done-signal trailer is exactly `Story: NN` on its own line, plus `Sprint: <sprint-name>`.
- Story enumeration globs `[0-9]*.md` within the sprint directory and skips `00-*`. Never `[0-9][0-9]-*.md`, which misses `06b-target-header-scale.md`.
- Evidence lives in `~/.sprint-evidence/<sprint>/<NN-slug>/`. Never `/tmp`, never inside a git worktree.
- No kickoff prompt may contain `git checkout main`. Trunk is checked out in a linked worktree and the command fails.
- Do not modify `~/lead-us` or delete anything outside `~/claude-skills` until Task 5, which is explicitly gated on the user's go-ahead.
- `~/claude-skills` has two unrelated dirty files (`codex/SKILL.md`, `codex/run-codex.sh`). Never `git add -A`; stage only the paths each step names.

---

### Task 1: Relocate both skills into the repo and dual-install

**Files:**
- Create: `~/claude-skills/sprint-orchestrator/SKILL.md` (moved content, unchanged)
- Create: `~/claude-skills/codex-execution-handoff/SKILL.md` (moved content, unchanged)
- Delete: `~/.claude/skills/sprint-orchestrator/` and `~/.claude/skills/codex-execution-handoff/` (real dirs, replaced by symlinks)
- Delete: `~/.codex/skills/sprint-orchestrator/` (drifted copy, replaced by symlink)

**Interfaces:**
- Consumes: nothing.
- Produces: `~/claude-skills/sprint-orchestrator/` and `~/claude-skills/codex-execution-handoff/` as the single source of truth for Tasks 2–4. Both reachable via symlink from `~/.claude/skills` and `~/.codex/skills`.

- [ ] **Step 1: Confirm the drifted Codex copy holds nothing unique**

The spec assumes `~/.codex/skills/sprint-orchestrator/SKILL.md` differs only in its description and two frontmatter keys. Prove it before overwriting.

```bash
diff ~/.codex/skills/sprint-orchestrator/SKILL.md ~/.claude/skills/sprint-orchestrator/SKILL.md
```

Expected: exactly one hunk, at line 3, changing the `description:` and adding `disable-model-invocation:` / `argument-hint:`. If any other hunk appears, STOP — the copy has unique content that must be reconciled by hand.

- [ ] **Step 2: Probe whether Codex tolerates the Claude-specific frontmatter key**

The spec makes symlinking into `~/.codex/skills` conditional on Codex not erroring on `disable-model-invocation: true`. Test it in a hermetic `CODEX_HOME`.

```bash
PROBE="$(mktemp -d)"
mkdir -p "$PROBE/skills/frontmatter-probe"
ln -s "$HOME/.codex/auth.json"   "$PROBE/auth.json"
ln -s "$HOME/.codex/config.toml" "$PROBE/config.toml"
cat > "$PROBE/skills/frontmatter-probe/SKILL.md" <<'EOF'
---
name: frontmatter-probe
description: Probe whether Codex tolerates Claude-specific frontmatter keys.
disable-model-invocation: true
argument-hint: [sprint-dir]
---
Reply with the single word PROBE-OK.
EOF
CODEX_HOME="$PROBE" codex exec -C "$HOME/claude-skills" \
  -c approval_policy=never --sandbox read-only \
  -c default_mode_request_user_input=false \
  "Reply with the single word READY." 2>&1 | tail -3
echo "exit=$?"
```

The `default_mode_request_user_input=false` override is load-bearing: the probe symlinks the real
`~/.codex/config.toml` into its "hermetic" home, and that file sets `default_mode_request_user_input = true`,
which makes `codex exec` block forever waiting on input. Without the override this command hangs
rather than answering the question.

Expected: `exit=0` and no parse/frontmatter error in the output. If Codex errors, skip Step 6 (the Codex symlink), leave `~/.codex/skills/sprint-orchestrator/` as a plain copied directory, and record the deviation in the spec's Packaging section.

This probe establishes only that Codex does not choke at startup on the unknown key — it places the
skill file, it does not invoke it. That is sufficient: if Codex parses frontmatter eagerly, a clean
start proves tolerance; if it parses lazily, the unknown key is never read at all. And
`disable-model-invocation` blocks *model* auto-invocation, not *user* invocation, so Codex planning a
sprint with `$sprint-orchestrator` is unaffected either way.

- [ ] **Step 3: Copy both skills into the repo and verify byte-identity**

```bash
cd ~/claude-skills
mkdir -p sprint-orchestrator codex-execution-handoff
cp ~/.claude/skills/sprint-orchestrator/SKILL.md      sprint-orchestrator/SKILL.md
cp ~/.claude/skills/codex-execution-handoff/SKILL.md  codex-execution-handoff/SKILL.md
diff ~/.claude/skills/sprint-orchestrator/SKILL.md      sprint-orchestrator/SKILL.md      && echo "orchestrator identical"
diff ~/.claude/skills/codex-execution-handoff/SKILL.md  codex-execution-handoff/SKILL.md  && echo "handoff identical"
```

Expected: both `identical` lines print. Only after both print is it safe to remove the originals.

- [ ] **Step 4: Commit the relocation before deleting anything**

```bash
cd ~/claude-skills
git add sprint-orchestrator/SKILL.md codex-execution-handoff/SKILL.md
git commit -m "chore(skills): track sprint-orchestrator and codex-execution-handoff"
```

- [ ] **Step 5: Replace the originals with symlinks via install.sh**

```bash
rm -rf ~/.claude/skills/sprint-orchestrator ~/.claude/skills/codex-execution-handoff
cd ~/claude-skills && ./install.sh
readlink ~/.claude/skills/sprint-orchestrator
readlink ~/.claude/skills/codex-execution-handoff
```

Expected: both `readlink` calls print paths under `~/claude-skills/`.

- [ ] **Step 6: Install into Codex's skills dir (skip if Step 2 failed)**

```bash
rm -rf ~/.codex/skills/sprint-orchestrator
cd ~/claude-skills && CLAUDE_SKILLS_DIR=~/.codex/skills ./install.sh
readlink ~/.codex/skills/sprint-orchestrator
readlink ~/.codex/skills/codex-execution-handoff
readlink ~/.codex/skills/codex
```

Expected: all three print paths under `~/claude-skills/`. Note that `install.sh` links *every* skill in the repo, so the `codex` skill lands in Codex's own skills dir too. That is harmless — it is a wrapper Codex will not invoke on itself — but confirm it appears rather than being surprised by it later.

- [ ] **Step 7: Commit**

Nothing to commit — Steps 5 and 6 only create symlinks outside the repo. Verify the tree is clean of new changes:

```bash
cd ~/claude-skills && git status --short
```

Expected: only the two pre-existing dirty files, `codex/SKILL.md` and `codex/run-codex.sh`.

---

### Task 2: `sprint-status.sh` — derive story state from git

**Files:**
- Create: `~/claude-skills/sprint-orchestrator/sprint-status.sh`
- Test: `~/claude-skills/sprint-orchestrator/test/test-sprint-status.sh`

**Interfaces:**
- Consumes: the repo layout from Task 1.
- Produces: `sprint-status.sh <sprint-dir>`, printing one `STATE NUM SLUG` line per story to stdout. `STATE` is one of `DONE`, `DOING`, `TODO`. Exit 2 on usage error or unresolvable trunk. Honours `SPRINT_TRUNK` (default `origin/main`). Task 3 references this script by path from `sprint-orchestrator/SKILL.md`.

The four test cases below are not hypothetical — each reproduces a state error observed in `~/lead-us` during the spec's dry run. Write them first.

- [ ] **Step 1: Write the failing test**

Create `~/claude-skills/sprint-orchestrator/test/test-sprint-status.sh`:

```bash
#!/usr/bin/env bash
# test-sprint-status.sh — each case reproduces a real misreport observed in ~/lead-us.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SUT="$HERE/../sprint-status.sh"
PASS=0; FAIL=0
ok() { PASS=$((PASS+1)); printf 'ok   - %s\n' "$1"; }
no() { FAIL=$((FAIL+1)); printf 'FAIL - %s\n' "$1"; }
# assert that story $2 has state $3 in the output $1
state_is() {
  local out="$1" num="$2" want="$3" got
  got="$(printf '%s\n' "$out" | awk -v n="$num" '$2==n {print $1}')"
  [ "$got" = "$want" ] && ok "story $num is $want" || no "story $num: want $want, got '${got:-<absent>}'"
}

REPO="$(mktemp -d)"; cd "$REPO"
git init -q -b main
git config user.email t@t; git config user.name t
SD="docs/sprints/s"; mkdir -p "$SD"
for f in 00-overview 01-alpha 02-beta 03-gamma 06-zeta 06b-delta; do echo "# $f" > "$SD/$f.md"; done
echo "# feedback" > "$SD/STORY-FEEDBACK.md"
git add -A && git commit -q -m "chore: seed sprint"

# Story 01 — DONE via trailer, branch deleted after a fast-forward merge.
# Regression: a deleted branch previously read TODO (lead-us stories 01 and 04).
git switch -qc sprint/01-alpha
echo work > a.txt && git add a.txt
git commit -q -m "$(printf 'feat: alpha\n\nStory: 01\nSprint: s\n')"
git switch -q main && git merge -q --ff-only sprint/01-alpha && git branch -qD sprint/01-alpha

# Story 02 — DOING: branch cut, zero commits, trunk then advances.
# Regression: this previously read DONE the moment trunk moved (lead-us story 10).
git branch sprint/02-beta main
echo more > b.txt && git add b.txt && git commit -q -m "chore: advance trunk"

# Story 03 — DONE via trailer, but a worktree still lingers on its merged branch.
# Regression: "worktree implies DOING" previously misreported this (lead-us story 07).
git switch -qc sprint/03-gamma
echo work > c.txt && git add c.txt
git commit -q -m "$(printf 'feat: gamma\n\nStory: 03\nSprint: s\n')"
git switch -q main && git merge -q --no-ff -m "Merge story 03" sprint/03-gamma
WT="$(mktemp -d)/wt03"
git worktree add -q "$WT" sprint/03-gamma

# Story 06 — DONE via trailer. Exists solely so that 06b can prove the `$` anchor holds:
# a `Story: 06` trailer must NOT satisfy story 06b.
git switch -qc sprint/06-zeta
echo work > z.txt && git add z.txt
git commit -q -m "$(printf 'feat: zeta\n\nStory: 06\nSprint: s\n')"
git switch -q main && git merge -q --ff-only sprint/06-zeta

# Story 06b — TODO, and must be enumerated at all.
# Regression: the old [0-9][0-9]-*.md glob skipped it entirely.

OUT="$(SPRINT_TRUNK=main "$SUT" "$SD" 2>&1)"
printf '%s\n' "$OUT"
echo "---"

state_is "$OUT" 01  DONE
state_is "$OUT" 02  DOING
state_is "$OUT" 03  DONE
state_is "$OUT" 06  DONE
state_is "$OUT" 06b TODO

# 00-overview and STORY-FEEDBACK must never appear as stories.
case "$OUT" in *overview*) no "00-overview excluded";; *) ok "00-overview excluded";; esac
case "$OUT" in *FEEDBACK*) no "STORY-FEEDBACK excluded";; *) ok "STORY-FEEDBACK excluded";; esac

# Usage errors exit 2.
SPRINT_TRUNK=main "$SUT" >/dev/null 2>&1; [ $? -eq 2 ] && ok "no args exits 2" || no "no args exits 2"
SPRINT_TRUNK=main "$SUT" /nonexistent >/dev/null 2>&1; [ $? -eq 2 ] && ok "bad dir exits 2" || no "bad dir exits 2"
SPRINT_TRUNK=nosuchref "$SUT" "$SD" >/dev/null 2>&1; [ $? -eq 2 ] && ok "bad trunk exits 2" || no "bad trunk exits 2"

git worktree remove --force "$WT" 2>/dev/null
printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
chmod +x ~/claude-skills/sprint-orchestrator/test/test-sprint-status.sh
~/claude-skills/sprint-orchestrator/test/test-sprint-status.sh
```

Expected: FAIL. The script under test does not exist, so every `state_is` reports `got '<absent>'`.

- [ ] **Step 3: Write the minimal implementation**

Create `~/claude-skills/sprint-orchestrator/sprint-status.sh`:

```bash
#!/usr/bin/env bash
# sprint-status.sh — derive story state from git. Nothing is stored, so nothing can drift.
#
#   DONE   a `Story: NN` trailer is reachable from trunk
#   DOING  a sprint/NN-* branch or a worktree pinned to one exists, and not DONE
#   TODO   neither
#
# DONE outranks DOING: merged branches and their worktrees linger.
set -euo pipefail

sprint_dir="${1:-}"
[ -n "$sprint_dir" ] || { echo "sprint-status: usage: sprint-status.sh docs/sprints/<sprint>" >&2; exit 2; }
[ -d "$sprint_dir" ] || { echo "sprint-status: no such directory: $sprint_dir" >&2; exit 2; }

trunk="${SPRINT_TRUNK:-origin/main}"
git rev-parse --verify --quiet "$trunk^{commit}" >/dev/null \
  || { echo "sprint-status: cannot resolve trunk '$trunk' — run 'git fetch origin', or set SPRINT_TRUNK" >&2; exit 2; }

worktree_branches="$(git worktree list --porcelain | sed -n 's|^branch refs/heads/||p')"

for doc in "$sprint_dir"/[0-9]*.md; do
  [ -e "$doc" ] || continue
  slug="$(basename "$doc" .md)"
  case "$slug" in 00-*) continue ;; esac
  num="${slug%%-*}"

  if [ -n "$(git log "$trunk" --grep="^Story: ${num}\$" --format=%h -1)" ]; then
    state=DONE
  elif printf '%s\n' "$worktree_branches" | grep -qx "sprint/$slug" \
    || git show-ref --verify --quiet "refs/heads/sprint/$slug" \
    || git show-ref --verify --quiet "refs/remotes/origin/sprint/$slug"; then
    state=DOING
  else
    state=TODO
  fi
  printf '%-6s %-4s %s\n' "$state" "$num" "$slug"
done
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
chmod +x ~/claude-skills/sprint-orchestrator/sprint-status.sh
~/claude-skills/sprint-orchestrator/test/test-sprint-status.sh
```

Expected: `10 passed, 0 failed`, exit 0.

- [ ] **Step 5: Verify against the real repo, where the old model was wrong**

This is the acceptance check. `~/lead-us` has no trailers yet, so every story must read `DOING` or `TODO` — never `DONE`. Critically, `10-alerts-analyzer` must read `DOING` (it has a live worktree), which the branch-ancestry model got wrong.

```bash
cd ~/lead-us && git fetch origin --quiet
~/claude-skills/sprint-orchestrator/sprint-status.sh docs/sprints/2026-07-07-report-delivery-sprint
```

Expected: no `DONE` rows at all (no trailers exist yet); `DOING 10 10-alerts-analyzer`; `TODO 06b 06b-target-header-scale`. This is read-only — it must not modify `~/lead-us`.

- [ ] **Step 6: Commit**

```bash
cd ~/claude-skills
git add sprint-orchestrator/sprint-status.sh sprint-orchestrator/test/test-sprint-status.sh
git commit -m "feat(sprint): derive story state from a Story: NN commit trailer"
```

---

### Task 3: Rewrite `sprint-orchestrator/SKILL.md`

**Files:**
- Modify: `~/claude-skills/sprint-orchestrator/SKILL.md`
- Create: `~/claude-skills/test/lint-skills.sh`

**Interfaces:**
- Consumes: `sprint-status.sh` from Task 2, referenced by relative path.
- Produces: `test/lint-skills.sh`, a repo-level invariant checker that Task 4 **appends** a second section to. Its `ok`/`no`/`has`/`hasnt` helpers are defined here and reused there.

- [ ] **Step 1: Write the failing lint test**

Create `~/claude-skills/test/lint-skills.sh`. These assertions encode the spec's success criteria 5, 6 and 7, plus the template contract from §2.

```bash
#!/usr/bin/env bash
# lint-skills.sh — invariants the sprint skills must hold. Prose is the product; lint it.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ORCH="$HERE/../sprint-orchestrator/SKILL.md"
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

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
```

- [ ] **Step 2: Run the lint to verify it fails**

```bash
chmod +x ~/claude-skills/test/lint-skills.sh
~/claude-skills/test/lint-skills.sh
```

Expected: FAIL. The current `SKILL.md` still contains `.CLAIMED.md`, `done/`, `do not merge`, and the `[0-9][0-9]-*.md` glob, and lacks every new field.

- [ ] **Step 3: Delete the four superseded sections**

In `~/claude-skills/sprint-orchestrator/SKILL.md`, remove these sections in full, including their headings:

- `## Filesystem State` — state is derived now, not stored.
- `## Claim And Run` — claiming is the executor's business, and there is nothing to rename.
- `## Integrate` — its mechanical half moves to `codex-execution-handoff`; its planning half is folded into Step 4 below.
- `## Find Open Stories` — replaced by `sprint-status.sh`.

Also delete two lines that the lint will otherwise catch:

- in `## Contract`: `Story state is the doc path. Do not add status frontmatter, ledger files, or tracker-derived done detection.`
- in `## Guardrails`: the bullet beginning ``` `.CLAIMED.md` is a convention, not a lock. ``` — there is no `.CLAIMED.md` any more, and branch existence is the taken-signal.

After these deletions, `grep -c 'CLAIMED\|done/' sprint-orchestrator/SKILL.md` must print `0`.

- [ ] **Step 4: Insert the derived-state section**

Insert this after `## Contract`, replacing where `## Filesystem State` used to be:

````markdown
## Story State Is Derived

Story state is never written down. It is computed from git, so it cannot drift.

| State | Signal |
|-------|--------|
| `DONE` | a `Story: NN` trailer is reachable from trunk |
| `DOING` | a `sprint/NN-*` branch or a worktree pinned to one exists, and not `DONE` |
| `TODO` | neither |

`DONE` outranks `DOING`: merged branches and the worktrees pinned to them linger long after the
work lands.

The trailer is a footer on every commit the executor makes for a story, so it survives branch
deletion, fast-forward, squash, and rebase:

```
feat(reports): add date range presets

Story: 07
Sprint: 2026-07-07-report-delivery-sprint
```

Read the current state with the helper, from the repo root:

```bash
~/.claude/skills/sprint-orchestrator/sprint-status.sh docs/sprints/<sprint>
```

Stories are enumerated from files matching `[0-9]*.md`, skipping `00-*`. Suffixed numbers such as
`06b` are first-class.

Sprints planned before this convention have no trailers and their history is not rewritten. For
those, `00-overview.md` and `STORY-FEEDBACK.md` are the record; `sprint-status.sh` will
under-report them and that is expected.
````

- [ ] **Step 5: Insert the planning half of integration**

Insert this after `## Plan Session`:

````markdown
## Integration Is Planned Here, Performed Elsewhere

Planning decides and records in `00-overview.md`: the merge order, the dependency edges, and the
shared-file hotspots that force stories to run serially. Sweeping `STORY-FEEDBACK.md` for follow-up
stories and unresolved product questions is also a plan-session activity.

Performing the merge in that order, resolving the named hotspots, deploying, and closing the tracker
card belong to `codex-execution-handoff`. Do not restate the lifecycle here.
````

- [ ] **Step 6: Update the story-doc template**

Replace the **entire fenced template block** inside `## Story Doc Shape` with exactly this. Note that the old template's `## Handoff` section is gone: there is no claim to record and no `done/` to move to.

````markdown
```markdown
---
story: 07
title: <short imperative>
conversation: "Story 07: Three Descriptive Words"
sprint: <sprint-name>
execution: autonomous        # autonomous | stop-at-pr — copied from 00-overview.md
flow: mechanical             # mechanical | design-heavy
branch: sprint/07-<slug>
depends_on: []
wave: 1
frontend: true               # does any user-visible surface change?
surfaces:                    # required iff frontend: true; the executor may extend it
  - route: /reports
    states: [populated, empty]
ownership:
  owns: [src/reports/**]
  owns_hunk:
    - src/app/(app)/reports/page.tsx  # ONLY the <ReportHeaderStrip> props
  do_not_touch: [src/app/layout.tsx]
  shared_note: >
    <what a neighbouring story owns in a file this story must read but not modify>
tracker_card:
---

# Story 07 - <title>

**Kickoff:** render the prompt with `codex-execution-handoff` for `07-<slug>.md`.

## Goal
<the single /goal line, nothing else>

## Objective
<Question to investigate, not the answer to implement.>

## Start by verifying
- <current code/doc/test/tool anchor to check first>

## Decisions already made
- <settled product or architecture decisions>

## In scope
- <work owned by this story>

## Out of scope
- <adjacent work and owning story>

## Browser Verification
1. <route, state, and what a human must see>

## Done means
- [ ] <observable success criterion>
- [ ] If output is a file, PDF, email, export, or other artifact, a human opened it and confirmed it.
```
````

`conversation:` is `Story NN: <Three Descriptive Words>`, written by the planner. It matches the
tracker's card-title convention, so the card and the executor's session share one name.

`execution:` is declared once in `00-overview.md` and copied into every story. A story doc is a
prompt for a fresh agent; it must not require reading the overview to learn whether it may merge.

`frontend:` is true when any user-visible surface changes — not when `ownership.owns` happens to
contain component paths. A pure `lib/` change that alters what a page renders is a frontend story.
When unsure, set it true and name the surface.

- [ ] **Step 7: Run the lint to verify it passes**

```bash
~/claude-skills/test/lint-skills.sh
```

Expected: `15 passed, 0 failed`, exit 0.

- [ ] **Step 8: Commit**

```bash
cd ~/claude-skills
git add sprint-orchestrator/SKILL.md test/lint-skills.sh
git commit -m "refactor(sprint): derive state, drop claim and integrate sections"
```

---

### Task 4: Rewrite `codex-execution-handoff/SKILL.md`

**Files:**
- Modify: `~/claude-skills/codex-execution-handoff/SKILL.md`
- Modify: `~/claude-skills/test/lint-skills.sh` (append a second section)

**Interfaces:**
- Consumes: `test/lint-skills.sh` and its `ok`/`no`/`has`/`hasnt` helpers from Task 3; the story-doc frontmatter contract from Task 3 Step 6.
- Produces: the final skill. Nothing depends on it.

- [ ] **Step 1: Append the failing lint assertions**

In `~/claude-skills/test/lint-skills.sh`, insert this block immediately before the `printf '\n%d passed` line:

```bash
# --- codex-execution-handoff ---
HAND="$HERE/../codex-execution-handoff/SKILL.md"
hasnt "handoff: never checks out trunk"      "git checkout main" "$HAND"
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
has   "handoff: stop-at-pr variant"          "stop-at-pr"        "$HAND"
has   "handoff: executor never invokes it"   "never invoked by the executing" "$HAND"
```

- [ ] **Step 2: Run the lint to verify it fails**

```bash
~/claude-skills/test/lint-skills.sh
```

Expected: the 15 orchestrator assertions pass; the 16 handoff assertions fail. The current file contains `HANDOFF.md`, `.CLAIMED.md`, and `invoke \`sprint-orchestrator\``, and lacks every new rule.

- [ ] **Step 3: Replace the Overview and companion sections**

Replace the `## Overview` section and the trailing `## Companion: sprint-orchestrator` section of `~/claude-skills/codex-execution-handoff/SKILL.md` with:

````markdown
## Overview

Render a kickoff prompt that hands ONE planned story to an autonomous coder, which runs the whole
lifecycle — plan → build → validate → merge to trunk → deploy → verify on the live app — and pings
the human **once**, at a story-specific `/goal` checkpoint kept as late as possible.

This skill is a prompt renderer for whoever plans. It is **never invoked by the executing story
session**, which already holds the rendered prompt and has no reason to read the renderer.

Companion to `sprint-orchestrator`, which writes the story docs this runs on. That skill is manual
only (`disable-model-invocation: true`), so read its story doc and `00-overview.md` directly rather
than trying to invoke it.
````

- [ ] **Step 4: Replace the kickoff-prompt template**

Replace the whole `## The kickoff prompt (template)` fenced block with:

````markdown
## The kickoff prompt (template)

First line is the story's `conversation:` value, so the Codex.app session takes the story's name.
Fill `{STORY_DOC}`, `{NN}`, `{SLUG}`, `{SPRINT}` and end with the story's `/goal`.

```
Story {NN}: {Three Descriptive Words}

You are executing ONE story. Run the full lifecycle below: plan, build, validate, then MERGE and
DEPLOY TO PROD, verify on prod, and hand it back to me (Rodion) with test instructions.

Read first: {STORY_DOC}, 00-overview.md (scope, locked decisions, merge order, your ownership lane),
STORY-FEEDBACK.md, and the repo conventions (AGENTS.md / CLAUDE.md). If any of those are absent from
this worktree, read them from trunk with `git show origin/main:<path>` — do not copy them in and do
not commit copies. The product scope and decisions in those docs are SETTLED. If you find a wrong
premise, an internal contradiction, or a genuine product ambiguity, STOP and ask me.

0. PREFLIGHT.
   - `git fetch origin`
   - If `sprint/{NN}-{SLUG}` already exists on any ref, the story is taken. STOP and report; never
     co-opt someone else's branch.
   - `git switch -c sprint/{NN}-{SLUG} origin/main`
     NEVER run `git checkout main`. Trunk is checked out in another worktree and the command fails.
   - Confirm this worktree is linked to the real Vercel project before any deploy (see AGENTS.md).

1. PLAN — brainstorm your own approach (design-heavy: weigh 2-3 options; mechanical: a short TDD
   plan). Do the doc's "Start by verifying"; reproduce the bug / establish the baseline BEFORE
   changing anything, capturing the "before" screenshots while you are there. Restate In/Out of scope.

2. IMPLEMENT — TDD: failing test first. Stay strictly inside `ownership.owns`; never touch
   `do_not_touch`. Every commit you make for this story carries the trailer:

       Story: {NN}
       Sprint: {SPRINT}

   This is the only record that the story landed. A commit without it is invisible to sprint status.

3. VALIDATE LOCALLY — tests + typecheck; drive the doc's Browser Verification locally; capture the
   "after" screenshots; open any produced artifact. Fix until green.

4. MERGE & DEPLOY — gate: story tests + typecheck + a production build must all pass, and the story's
   commits must carry the `Story: {NN}` trailer. Merge into trunk in the overview's merge order;
   ensure trunk is green. If the push is rejected because another session landed first, run
   `git pull --rebase` and retry ONCE. If it is rejected again, STOP and report — do not force-push
   and do not keep retrying. Deploy with the project's deploy command.

5. VERIFY ON PROD — drive the Browser Verification against the LIVE URL with a real test account;
   capture prod screenshots. Defect -> fix, re-gate, redeploy, re-check. If prod breaks and it is not
   a fast fix -> roll back (or revert the merge) and tell me. Never leave prod broken.

6. HAND OFF — append findings to STORY-FEEDBACK.md, including any surface you had to add to
   `surfaces:`. Produce the "How to test this yourself" section. Move the tracker card to Done. State
   branch, files, tests + results, deploy id.

Finally — this is your goal and the first (ideally only) point you check back with me. Work the whole
lifecycle autonomously toward it. Surface earlier ONLY for: a wrong premise or genuine product
ambiguity; an inability to keep prod green; or if no approved driver can drive the browser
verification.

/goal {STORY_GOAL}
```

Under `execution: stop-at-pr`, steps 4 and 5 collapse to: open a PR, do not merge, do not deploy.
The trailer still goes on the commits; `DONE` flips when the human merges.
````

- [ ] **Step 5: Replace the evidence and verification rules**

Replace the `## Deploy gate + rollback (non-negotiable)` and `## The "How to test this yourself" hand-back format` sections with:

````markdown
## Deploy gate + rollback (non-negotiable)
- Gate EVERY deploy on: story tests + typecheck + a production build + the `Story: NN` trailer being
  present on the story's commits. A broken build never reaches prod, and an untrailered story is
  invisible to sprint status.
- If the live check fails and is not a fast fix: roll back the deploy (or revert the merge) and
  report. Never leave prod broken.

## Evidence (frontend stories)

`surfaces:` in the story doc is a floor, not a ceiling. It is knowable roughly at plan time, not
exhaustively. When verification reveals a surface the planner missed, add it, capture it, and record
the addition in STORY-FEEDBACK.md.

For each `(route, state)`: **before** and **after** locally, plus **after** on the live URL.

A screenshot from an **approved driver** is mandatory. The project's AGENTS.md names which drivers
are approved. Banned unconditionally:

- a DOM class or attribute check standing in for a screenshot;
- any driver not listed in AGENTS.md;
- omitting which driver produced a shot.

If no approved driver can drive the flow, HALT and report what you tried. Every shot declares its
provenance:

| Surface | State | Driver | Viewport | Role | Client |
|---|---|---|---|---|---|
| `/reports` | targets set | in-app connector | 1280x720 | admin | MyWhisky |

Files land in `~/.sprint-evidence/{SPRINT}/{NN}-{SLUG}/`. Never `/tmp`, and never inside a git
worktree — a worktree is deleted long before a reboot, taking the evidence with it.

**This skill targets Codex.app, which renders images.** The hand-back embeds the screenshots inline
in its final message, grouped before/after per surface. That is the human's confirmation step. Do not
attempt to attach them to the tracker card: the Asana V2 MCP exposes no attachment-upload tool and
its tokens do not work with the REST API. The written hand-back reaches the card via `add_comment`.

With `frontend: false`, no screenshots — but a produced artifact (PDF, email, export) must still be
opened and confirmed.

## The "How to test this yourself" hand-back format
What changed · Where = live URL + role/account · Steps (exact clicks/inputs, expected vs observed on
prod) · Test data/accounts · Evidence (inline screenshots + the provenance table) · Risk + how to roll
back · Checks run (commands + results, build, deploy id) · Open questions.
````

- [ ] **Step 6: Update Common mistakes**

Replace the `## Common mistakes` list with:

````markdown
## Common mistakes
- **`git checkout main`** — trunk lives in another worktree; the command fails. Use `git switch -c <branch> origin/main`.
- **Commits without the `Story: NN` trailer** — the story ships and sprint status still calls it TODO.
- **Co-opting an existing `sprint/NN-*` branch** instead of stopping. It means someone else has the story.
- **Force-pushing after a rejected push.** Rebase once, retry once, then stop and report.
- **Deploying from a feature branch** instead of merging to trunk first — "live" then ≠ what you tested.
- **A `/goal` that is an early checkpoint** ("open a PR") → the agent pings before it is live.
- **Silently swapping browser drivers** — the substitution is legal only if AGENTS.md approves the driver and the hand-back declares it.
- **Writing evidence to `/tmp` or into the worktree** — both vanish before review.
- **Progress pings mid-run** → defeats the single-checkpoint purpose.
````

- [ ] **Step 7: Run the lint to verify it passes**

```bash
~/claude-skills/test/lint-skills.sh
```

Expected: `31 passed, 0 failed`, exit 0.

- [ ] **Step 8: Run the full test suite**

```bash
~/claude-skills/sprint-orchestrator/test/test-sprint-status.sh && ~/claude-skills/test/lint-skills.sh
```

Expected: both suites pass, exit 0.

- [ ] **Step 9: Commit**

```bash
cd ~/claude-skills
git add codex-execution-handoff/SKILL.md test/lint-skills.sh
git commit -m "refactor(handoff): worktree-safe branching, trailer, approved-driver evidence"
```

---

### Task 5: `~/lead-us` migration and stale-copy removal — GATED

**Files:**
- Modify: `~/lead-us/AGENTS.md`, `~/lead-us/CLAUDE.md`, `~/lead-us/.gitignore`
- Delete: `~/lead-us/docs/sprints/2026-07-07-report-delivery-sprint/HANDOFF.md`
- Rename: 18 `*.CLAIMED.md` docs across both sprint dirs back to `*.md`
- Delete: `~/Downloads/sprint-orchestrator-skill/`, `~/Documents/Codex/2026-07-07/files-mentioned-by-the-user-name/outputs/sprint-orchestrator/`

**Interfaces:**
- Consumes: the finished skills from Tasks 3 and 4.
- Produces: nothing other tasks depend on.

**STOP.** This task modifies a different repository and deletes files. Do not begin it without the user's explicit go-ahead, item by item. Deleting files and overwriting user data are on the user's stop-and-ask list. Present each sub-step and wait.

- [ ] **Step 1: Ask for go-ahead, item by item**

Present these five items and get an explicit yes for each before touching anything:

1. Revert 18 `*.CLAIMED.md` docs to `*.md` (state is derived now; the suffix is meaningless and misleading).
2. Delete `2026-07-07-report-delivery-sprint/HANDOFF.md` (superseded by the skill).
3. Rename `2026-07-02-functional-sprint/00-sprint-overview.md` to `00-overview.md`.
4. Add the approved-driver list and the Vercel gotcha to `AGENTS.md` and `CLAUDE.md`.
5. Delete the two stale skill copies outside `~/claude-skills`.

- [ ] **Step 2: Record the project facts in AGENTS.md and CLAUDE.md**

Both files are byte-identical today; apply the same edit to each. Append to the Gotchas section:

```markdown
- **Approved visual-verification drivers.** Browser evidence for a sprint story must come from one of:
  the in-app browser connector, or Playwright Core driving system Chrome. Every screenshot must declare
  which driver, viewport, role, and client produced it. A DOM class check never substitutes for a
  screenshot. If neither driver can drive the flow, halt the story and report.
- **A fresh worktree auto-links to the wrong Vercel project.** It attaches to the throwaway `lead-us`
  project, whose env lacks Supabase keys, and the build fails at `/no-access`. Copy
  `.vercel/project.json` from the main checkout and re-pull prod env before `vercel build --prod`.
```

Do **not** write "when the connector times out, use Playwright" as a workaround. The driver list makes
Playwright legitimate; silence about which driver ran is the thing being banned.

- [ ] **Step 3: Ignore the old evidence path and revert the state suffixes**

```bash
cd ~/lead-us
printf '\n# sprint evidence is written to ~/.sprint-evidence, never here\n' >> .gitignore
for f in docs/sprints/*/*.CLAIMED.md; do git mv "$f" "${f%.CLAIMED.md}.md"; done
git rm docs/sprints/2026-07-07-report-delivery-sprint/HANDOFF.md
git mv docs/sprints/2026-07-02-functional-sprint/00-sprint-overview.md \
       docs/sprints/2026-07-02-functional-sprint/00-overview.md
```

- [ ] **Step 4: Verify sprint-status reads the migrated sprint sanely**

```bash
cd ~/lead-us && git fetch origin --quiet
~/claude-skills/sprint-orchestrator/sprint-status.sh docs/sprints/2026-07-07-report-delivery-sprint
```

Expected: `DOING 10 10-alerts-analyzer`, `TODO 06b 06b-target-header-scale`, and no `DONE` rows —
these stories predate the trailer and will never report `DONE`. That is the documented legacy
consequence, not a bug.

- [ ] **Step 5: Commit**

```bash
cd ~/lead-us
git add -- AGENTS.md CLAUDE.md .gitignore docs/sprints
git commit -m "chore(sprint): derive story state, record approved drivers"
```

- [ ] **Step 6: Delete the stale skill copies**

Only after the user confirms item 5:

```bash
rm -rf ~/Downloads/sprint-orchestrator-skill
rm -rf ~/Documents/Codex/2026-07-07/files-mentioned-by-the-user-name/outputs/sprint-orchestrator
```
