# Sprint Supervisor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rework `sprint-orchestrator` + `agent-handoff` per `docs/superpowers/specs/2026-07-14-sprint-supervisor-design.md`: launch-surface model advice, sprint-brief gate, supervisor lifecycle (dispatch/supervise/integrate, ownership transfer, DISPOSED events, planner handoff, demotion), a `~/.sprint-mail` mailbox with a new `sprint-mail.sh`, and matching lint/test updates.

**Architecture:** Prose is the product — SKILL.md/EXECUTION.md text IS the deployed behavior (symlinked live into `~/.claude/skills/` and `~/.codex/skills/`). Every prose invariant is pinned by `test/lint-skills.sh`; mechanics live in bash scripts with hermetic bash tests. TDD here means: add the lint pin or test first, watch it fail, write the prose/code, watch it pass.

**Tech Stack:** bash 3.2 (macOS default — no `flock`, no bash-4 features), coreutils, git, grep/awk/sed. No YAML parser, no other runtime.

## Global Constraints

- Every edit to `SKILL.md` / `EXECUTION.md` / `agents/openai.yaml` is a live deploy to both harnesses.
- Lint pins change in the SAME commit as the prose they pin (repo rule in `CLAUDE.md`).
- Frontmatter: `name:` equals directory name; a `description:` containing a colon must be a double-quoted scalar.
- Never write `git checkout main` un-negated in agent-handoff files (lint enforces).
- Conventional commits, explicit staged paths, never `git add -A`.
- All suites green after every task: `test/lint-skills.sh`, `sprint-orchestrator/test/test-sprint-status.sh`, `sprint-orchestrator/test/test-wave-handoffs.sh`, plus `sprint-orchestrator/test/test-sprint-mail.sh` once it exists.
- The spec is the source of truth: `docs/superpowers/specs/2026-07-14-sprint-supervisor-design.md`.
- Mailbox message filename grammar, fixed: `NN-SSS-<kind>.md`; kinds `evidence|question|concluded|reply|note`; outcomes `merged|pr-ready|handback|blocked|failed|dossier`.
- Mailbox root, fixed: `~/.sprint-mail/<repo-basename>/<sprint-dir-basename>/` (env override `SPRINT_MAIL_ROOT` for tests; poll override `SPRINT_MAIL_POLL`).

---

### Task 1: `sprint-mail.sh` + its test suite

**Files:**
- Create: `sprint-orchestrator/sprint-mail.sh` (mode 755)
- Create: `sprint-orchestrator/test/test-sprint-mail.sh` (mode 755)

**Interfaces:**
- Produces: `sprint-mail.sh post <sprint-dir> <NN> <kind> [<file>|-]` → prints created path, exit 0; exit 2 on bad input. `sprint-mail.sh list <sprint-dir> [<NN>]` → mtime-ordered full paths. `sprint-mail.sh wait <sprint-dir> <name-or-glob> [<timeout-seconds>]` → prints first matching path exit 0, exit 1 on timeout, default timeout 1800s, poll `${SPRINT_MAIL_POLL:-20}`s.
- Mail dir: `${SPRINT_MAIL_ROOT:-$HOME/.sprint-mail}/<repo-basename>/<basename of sprint-dir>` where repo-basename is derived from the git *common* dir of the CWD (worktree-safe).
- Sequencing: executor counter spans `evidence|question|concluded`; `reply` reuses the sequence of the story's newest unanswered `question`; `note` has its own counter. `concluded` bodies must start with `outcome: <merged|pr-ready|handback|blocked|failed|dossier>`.

- [ ] **Step 1: Write the failing test suite**

Create `sprint-orchestrator/test/test-sprint-mail.sh`:

```bash
#!/usr/bin/env bash
# Hermetic tests for sprint-mail.sh — the executor↔supervisor mailbox helper.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SUT="$HERE/../sprint-mail.sh"
PASS=0; FAIL=0
ok() { PASS=$((PASS+1)); printf 'ok   - %s\n' "$1"; }
no() { FAIL=$((FAIL+1)); printf 'FAIL - %s\n' "$1"; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export SPRINT_MAIL_ROOT="$TMP/mailroot"
export SPRINT_MAIL_POLL=1

# Fixture repo (repo basename namespaces the mailbox).
REPO_A="$TMP/repo-alpha"
mkdir -p "$REPO_A" && git -C "$REPO_A" init -q
cd "$REPO_A"
SPRINT="docs/sprints/2026-07-14-fixture-sprint"

# ---- post: creates, sequences, zero-pads ----
p1="$(printf 'found a thing\n' | "$SUT" post "$SPRINT" 07 evidence -)"
[ "$(basename "$p1")" = "07-001-evidence.md" ] && ok "first post is 07-001-evidence.md" || no "first post is 07-001-evidence.md (got: $p1)"
[ -f "$p1" ] && grep -q 'found a thing' "$p1" && ok "post body written" || no "post body written"
case "$p1" in "$SPRINT_MAIL_ROOT/repo-alpha/2026-07-14-fixture-sprint/"*) ok "mail dir is root/repo/sprint" ;; *) no "mail dir is root/repo/sprint (got: $p1)" ;; esac

p2="$(printf 'which auth flow?\n' | "$SUT" post "$SPRINT" 07 question -)"
[ "$(basename "$p2")" = "07-002-question.md" ] && ok "executor counter increments across kinds" || no "executor counter increments across kinds (got: $p2)"

# ---- reply: reuses the open question's sequence ----
p3="$(printf 'use flow B\n' | "$SUT" post "$SPRINT" 07 reply -)"
[ "$(basename "$p3")" = "07-002-reply.md" ] && ok "reply reuses question sequence" || no "reply reuses question sequence (got: $p3)"
printf 'x\n' | "$SUT" post "$SPRINT" 07 reply - >/dev/null 2>&1 \
  && no "reply with no open question is rejected" || ok "reply with no open question is rejected"

# ---- note: independent supervisor counter ----
p4="$(printf 'heads up\n' | "$SUT" post "$SPRINT" 07 note -)"
[ "$(basename "$p4")" = "07-001-note.md" ] && ok "note counter is independent" || no "note counter is independent (got: $p4)"

# ---- concluded: outcome line enforced ----
printf 'no outcome here\n' | "$SUT" post "$SPRINT" 07 concluded - >/dev/null 2>&1 \
  && no "concluded without outcome rejected" || ok "concluded without outcome rejected"
p5="$(printf 'outcome: pr-ready\nPR #12\n' | "$SUT" post "$SPRINT" 07 concluded -)"
[ "$(basename "$p5")" = "07-003-concluded.md" ] && ok "concluded takes next executor sequence" || no "concluded takes next executor sequence (got: $p5)"

# ---- input validation ----
printf 'x\n' | "$SUT" post "$SPRINT" 07 shout - >/dev/null 2>&1 \
  && no "unknown kind rejected" || ok "unknown kind rejected"
printf 'x\n' | "$SUT" post "$SPRINT" '../evil' evidence - >/dev/null 2>&1 \
  && no "non-numeric story rejected" || ok "non-numeric story rejected"
printf 'x\n' | "$SUT" post "$SPRINT" 06b evidence - >/dev/null 2>&1 \
  && ok "suffixed story number accepted" || no "suffixed story number accepted"

# ---- list: mtime order, story filter, no tmp litter ----
printf 'other story\n' | "$SUT" post "$SPRINT" 03 evidence - >/dev/null
n_all="$("$SUT" list "$SPRINT" | wc -l | tr -d ' ')"
[ "$n_all" = "7" ] && ok "list shows all messages" || no "list shows all messages (got: $n_all)"
n_07="$("$SUT" list "$SPRINT" 07 | grep -c '/07-')"
[ "$n_07" = "5" ] && ok "list filters by story" || no "list filters by story (got: $n_07)"
"$SUT" list "$SPRINT" | grep -q '\.tmp' && no "no tmp files visible" || ok "no tmp files visible"

# ---- wait: hit, deterministic miss, timeout ----
w1="$("$SUT" wait "$SPRINT" "07-002-reply.md" 3)" \
  && [ "$(basename "$w1")" = "07-002-reply.md" ] \
  && ok "wait finds an existing exact name" || no "wait finds an existing exact name"
"$SUT" wait "$SPRINT" "07-009-reply.md" 2 >/dev/null 2>&1 \
  && no "wait for absent reply times out exit 1 (stale 002 reply must not match)" \
  || ok "wait for absent reply times out exit 1 (stale 002 reply must not match)"
( sleep 2; printf 'late\n' | "$SUT" post "$SPRINT" 03 question - >/dev/null ) &
w2="$("$SUT" wait "$SPRINT" "03-*-question.md" 6)" \
  && ok "wait picks up a file posted mid-wait" || no "wait picks up a file posted mid-wait"
wait

# ---- repo namespacing: same sprint name in another repo → different mailbox ----
REPO_B="$TMP/repo-beta"; mkdir -p "$REPO_B" && git -C "$REPO_B" init -q
cd "$REPO_B"
pB="$(printf 'x\n' | "$SUT" post "$SPRINT" 07 evidence -)"
[ "$(basename "$pB")" = "07-001-evidence.md" ] && ok "fresh counter in second repo" || no "fresh counter in second repo (got: $pB)"
case "$pB" in "$SPRINT_MAIL_ROOT/repo-beta/"*) ok "second repo gets its own mailbox" ;; *) no "second repo gets its own mailbox (got: $pB)" ;; esac

# ---- concurrent posts from both senders: no loss (split counters, distinct names) ----
cd "$REPO_A"
( printf 'n\n' | "$SUT" post "$SPRINT" 07 note - >/dev/null ) &
( printf 'e\n' | "$SUT" post "$SPRINT" 07 evidence - >/dev/null ) &
wait
MDIR="$SPRINT_MAIL_ROOT/repo-alpha/2026-07-14-fixture-sprint"
[ -f "$MDIR/07-002-note.md" ] && [ -f "$MDIR/07-004-evidence.md" ] \
  && ok "concurrent posts from both senders both land" \
  || no "concurrent posts from both senders both land"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
```

- [ ] **Step 2: Run it to make sure it fails**

Run: `chmod +x sprint-orchestrator/test/test-sprint-mail.sh && sprint-orchestrator/test/test-sprint-mail.sh; echo "exit: $?"`
Expected: FAILs (SUT missing), non-zero exit.

- [ ] **Step 3: Implement `sprint-orchestrator/sprint-mail.sh`**

```bash
#!/usr/bin/env bash
# sprint-mail.sh — transient executor↔supervisor mail for one sprint.
#
#   sprint-mail.sh post <sprint-dir> <NN> <kind> [<file>|-]
#   sprint-mail.sh list <sprint-dir> [<NN>]
#   sprint-mail.sh wait <sprint-dir> <name-or-glob> [<timeout-seconds>]
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
set -euo pipefail

MAIL_ROOT="${SPRINT_MAIL_ROOT:-$HOME/.sprint-mail}"
POLL="${SPRINT_MAIL_POLL:-20}"

usage() {
  cat >&2 <<'EOF'
usage: sprint-mail.sh post <sprint-dir> <NN> <evidence|question|concluded|reply|note> [<file>|-]
       sprint-mail.sh list <sprint-dir> [<NN>]
       sprint-mail.sh wait <sprint-dir> <name-or-glob> [<timeout-seconds>]
EOF
  exit 2
}
err() { echo "sprint-mail: $1" >&2; exit 2; }

cmd="${1:-}"; sprint_dir="${2:-}"
[ -n "$cmd" ] && [ -n "$sprint_dir" ] || usage

repo_name() {
  local common
  common="$(git rev-parse --git-common-dir 2>/dev/null)" \
    || err "not inside a git repo — run from the project so the mailbox can be namespaced by repo"
  common="$(cd "$common" && pwd)"
  basename "$(dirname "$common")"
}
mail_dir="$MAIL_ROOT/$(repo_name)/$(basename "$sprint_dir")"

next_seq() {  # $1=story  $2=ERE matching the kinds sharing this counter
  local max
  max="$(ls "$mail_dir" 2>/dev/null \
    | sed -n -E "s/^$1-([0-9]{3})-($2)\.md\$/\1/p" | sort -n | tail -1)"
  printf '%03d' "$(( ${max:-0} + 1 ))"
}

case "$cmd" in
  post)
    nn="${3:-}"; kind="${4:-}"; src="${5:--}"
    [ -n "$nn" ] && [ -n "$kind" ] || usage
    echo "$nn" | grep -qE '^[0-9]+[a-z]?$' || err "story must look like 07 or 06b (got: $nn)"
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
  *) usage ;;
esac
```

Then: `chmod +x sprint-orchestrator/sprint-mail.sh`

- [ ] **Step 4: Run the suite until green**

Run: `sprint-orchestrator/test/test-sprint-mail.sh`
Expected: `21 passed, 0 failed`, exit 0. Also run the neighbors to prove no collateral: `test/lint-skills.sh && sprint-orchestrator/test/test-sprint-status.sh && sprint-orchestrator/test/test-wave-handoffs.sh` — all green.

- [ ] **Step 5: Commit**

```bash
git add sprint-orchestrator/sprint-mail.sh sprint-orchestrator/test/test-sprint-mail.sh
git commit -m "feat(sprint): add sprint-mail.sh mailbox helper"
```

---

### Task 2: Model guidance out of the skill body, onto launch surfaces

**Files:**
- Modify: `sprint-orchestrator/SKILL.md` (frontmatter description; delete "Run This on the Strongest Model"; one wording sweep)
- Modify: `agent-handoff/EXECUTION.md` (one wording sweep)
- Modify: `sprint-orchestrator/README.md` (new "Where to run it" section)
- Modify: `README.md` (root — table row)
- Modify: `sprint-orchestrator/agents/openai.yaml` (role wording)
- Modify: `test/lint-skills.sh` (flip the strongest-model pin; add new pins)

**Interfaces:**
- Produces: the phrase `a fresh planner session` (used verbatim by later tasks and pinned); README heading `## Where to run it`.

- [ ] **Step 1: Flip/add lint pins first (the failing test)**

In `test/lint-skills.sh`, add near the top (after the `ORCH_YAML=` line):

```bash
ORCH_README="$HERE/../sprint-orchestrator/README.md"
```

Replace the line `has   "orchestrator: strongest-model gate"  "Strongest Model"    "$ORCH"` with:

```bash
# The running agent must never reason about its own model. Launch advice is README-only:
# frontmatter description is harness-visible and could re-trigger self-disqualification.
hasnt "orchestrator: no self-model gate"        "Strongest Model"    "$ORCH"
hasnt "orchestrator: no self-identification"    "name the model you are running as" "$ORCH"
hasnt "orchestrator: no relaunch offer"         "so the user can relaunch" "$ORCH"
hasnt "orchestrator: no strongest-model remnant" "strongest-model"   "$ORCH"
hasnt "orchestrator: no launch advice in frontmatter" "Best run on"  "$ORCH"
has   "orchestrator readme: where-to-run advice" "## Where to run it" "$ORCH_README"
has   "orchestrator readme: fable preferred"     "Fable"             "$ORCH_README"
```

And in the EXECUTION.md block add:

```bash
hasnt "contract: no strongest-model remnant"  "strongest-model"    "$AHEXEC"
```

- [ ] **Step 2: Run lint to verify the new pins fail**

Run: `test/lint-skills.sh | grep -E 'FAIL|passed'`
Expected: FAILs for "no self-model gate", "no strongest-model remnant" (×2), "where-to-run advice", "fable preferred".

- [ ] **Step 3: Edit the prose**

`sprint-orchestrator/SKILL.md` — replace the description line with:

```yaml
description: Manual sprint command that plans verified story handoffs, dispatches them, supervises the wave to conclusion, and integrates results. Invoke explicitly with /sprint-orchestrator (Claude) or $sprint-orchestrator (Codex).
```

Delete the whole section (heading + paragraph):

```markdown
## Run This on the Strongest Model

Sprint planning is coverage-shaped — every candidate is verified against source truth — so it
gets the most capable model available, in its orchestration mode. First, name the model you are
running as. If it is not the strongest tier reachable right now (today: Fable with ultracode,
else Opus with ultracode, on Claude Code; Sol at `ultra` effort on Codex), say so and offer to
stop so the user can relaunch. No hard block — but proceeding on a lesser model needs the user's
explicit go-ahead, recorded in `00-overview.md`.
```

Change `re-enter planning in a fresh strongest-model
session, never in the executor's thread.` → `re-enter planning in a fresh planner session,
never in the executor's thread.`

`agent-handoff/EXECUTION.md` — change `Re-entering planning is the operator's move, in a fresh strongest-model planner
  session — never this session, which sits in a story worktree on a stale branch.` → `Re-entering planning is the operator's move, in a fresh planner session — never this
  session, which sits in a story worktree on a stale branch.`

`sprint-orchestrator/README.md` — insert after the "Pairs with…" paragraph:

```markdown
## Where to run it

Sprint orchestration is judgment-heavy, shortcut-friendly work: it prunes, reframes, and
re-scopes constantly. Run the planner on Anthropic models — **Fable** preferred, **Opus** as the
fallback. Codex models execute stories well, but as planners they follow process too literally
to cut short what deserves cutting short. This is launch advice for you, the operator — the
running skill never checks or names its own model. Story-level routing is unaffected: the
planner still routes each story with the tier ladder.
```

Root `README.md` — replace the sprint-orchestrator table row with:

```markdown
| [`sprint-orchestrator`](sprint-orchestrator/) | Plans verified story handoffs, supervises the wave, and integrates results; story state derived from git. Run it on Claude — Fable, else Opus |
```

`sprint-orchestrator/agents/openai.yaml` — replace `short_description: "Plan sprint story handoffs"` with `short_description: "Plan, dispatch, and supervise sprint stories"`.

- [ ] **Step 4: Verify green**

Run: `test/lint-skills.sh && sprint-orchestrator/test/test-wave-handoffs.sh && sprint-orchestrator/test/test-sprint-status.sh`
Expected: all pass, 0 failed.

- [ ] **Step 5: Commit**

```bash
git add sprint-orchestrator/SKILL.md agent-handoff/EXECUTION.md sprint-orchestrator/README.md README.md sprint-orchestrator/agents/openai.yaml test/lint-skills.sh
git commit -m "feat(sprint): move planner model advice to launch surfaces"
```

---

### Task 3: Sprint brief gate

**Files:**
- Modify: `sprint-orchestrator/SKILL.md` (new section before "## Plan Session")
- Modify: `test/lint-skills.sh`

**Interfaces:**
- Produces: `## Sprint brief` as the pinned name of the overview's opening section; the three-case predicate wording pinned by lint.

- [ ] **Step 1: Add lint pins**

In the orchestrator block of `test/lint-skills.sh`:

```bash
has   "orchestrator: brief gate section"        "## The Sprint Brief" "$ORCH"
has   "orchestrator: brief lands in overview"   "## Sprint brief"     "$ORCH"
has   "orchestrator: brief legacy case"         "do not force a backfill" "$ORCH"
has   "orchestrator: brief partial case"        "Never run first-run creation" "$ORCH"
```

- [ ] **Step 2: Run lint — expect those 4 FAILs**

Run: `test/lint-skills.sh | grep FAIL`

- [ ] **Step 3: Insert the section into `sprint-orchestrator/SKILL.md`, directly above `## Plan Session`**

```markdown
## The Sprint Brief

What exists in the sprint directory decides how a session opens:

- **Undefined** — no sprint directory, or one holding neither story docs nor `00-overview.md`:
  discuss the sprint with the user first — what it is about, what is in, what is out, what done
  looks like. Print a **Sprint brief** on screen in colloquial, simple English and iterate until
  the user approves it. Until then nothing else happens: no verification sweep, no story docs,
  no writes. The approved brief lands verbatim as the opening `## Sprint brief` section of
  `00-overview.md`.
- **Legacy** — `00-overview.md` exists without a `## Sprint brief` section: skip the gate and
  do not force a backfill; the overview as written is the scope boundary. Backfill only if the
  user asks.
- **Partial** — story docs or `STORY-FEEDBACK.md` exist but `00-overview.md` does not: stop and
  ask the user how to recover. Never run first-run creation over an existing partial directory.

On every re-invocation of a defined sprint, re-read the brief (when present) as the boundary
all planning stays inside. The brief is the one human-facing artifact; the rest of the overview
and the story docs stay dense and agent-facing.
```

- [ ] **Step 4: Verify green** — `test/lint-skills.sh` → 0 failed.

- [ ] **Step 5: Commit**

```bash
git add sprint-orchestrator/SKILL.md test/lint-skills.sh
git commit -m "feat(sprint): sprint brief gate with three entry cases"
```

---

### Task 4: Executor mailbox contract in EXECUTION.md + kickoff template line

**Files:**
- Modify: `agent-handoff/EXECUTION.md` (new `## Mailbox` section; outcome posts woven into every exit; softened non-interactive divergence)
- Modify: `agent-handoff/SKILL.md` (Mailbox line in the story-execution template)
- Modify: `test/lint-skills.sh`

**Interfaces:**
- Consumes: `sprint-mail.sh` command shapes from Task 1.
- Produces: the pinned phrases `The mailbox is never state` and `outcome: <merged | pr-ready | handback | blocked | failed | dossier>`; the template line `Mailbox: {MAILBOX} — post evidence, questions, and your terminal outcome per the contract's Mailbox section.` ({MAILBOX} = literal `~/.sprint-mail/<repo-basename>/{SPRINT}/`, resolved at render time). Task 7 makes the renderer print the same line.

- [ ] **Step 1: Add lint pins**

In the EXECUTION.md block:

```bash
has   "contract: mailbox section"            "## Mailbox"         "$AHEXEC"
has   "contract: mailbox never state"        "The mailbox is never state" "$AHEXEC"
has   "contract: outcome enum"               "outcome: <merged | pr-ready | handback | blocked | failed | dossier>" "$AHEXEC"
has   "contract: mailbox degrades"           "degrades to the handback protocol" "$AHEXEC"
has   "contract: one open question"          "One open question at a time" "$AHEXEC"
has   "contract: notes read before merge"    "notes before merge or PR" "$AHEXEC"
```

In the agent-handoff SKILL.md block:

```bash
has   "handoff: mailbox line in template"    "Mailbox: {MAILBOX}" "$AH"
```

- [ ] **Step 2: Run lint — expect those 7 FAILs**

- [ ] **Step 3: Edit `agent-handoff/EXECUTION.md`**

Insert this section between step "## 8. Hand off" and "## Divergences and handback":

```markdown
## Mailbox

Transient mail between you and the sprint supervisor lives at
`~/.sprint-mail/<repo-basename>/<sprint-basename>/` — your kickoff prompt names the literal
path. Post and read with `sprint-mail.sh` (beside `sprint-status.sh` in the
sprint-orchestrator skill directory). Files are `NN-SSS-<kind>.md`, append-only, never edited.

- `evidence` — findings that may affect other stories. Post and keep working; no reply comes.
- `question` — a blocking question inside this story's scope. Post it, then wait on the reply,
  which reuses your question's sequence — an exact filename:
  `sprint-mail.sh wait <sprint-dir> {NN}-{SSS}-reply.md 1800`. One open question at a time. A
  reply that arrives after your wait timed out is void — by then you are on the fallback path.
- `concluded` — posted once, on EVERY exit (below).
- Check for new `note` messages from the supervisor at each numbered step boundary, and read
  all of your story's notes before merge or PR.

The mailbox is never state: DONE is still both trailers on a trunk-reachable commit, and
`sprint-status.sh` never reads the mailbox. When nobody answers, the mailbox degrades to the
handback protocol — nothing new to learn, just faster when it works.

**Terminal outcome.** Every exit posts `concluded`, first line
`outcome: <merged | pr-ready | handback | blocked | failed | dossier>`, body naming the
terminal artifact (PR / dossier / branch) and where the hand-back evidence lives. After posting
it you are done — never resume the story afterwards. Fixes arrive as a fresh kickoff under an
ownership transfer, not as notes to a session that no longer exists.
```

Append to the "## 8. Hand off" list:

```markdown
- Post the terminal outcome: `concluded` with `outcome: merged` (AUTONOMOUS) or
  `outcome: pr-ready` (STOP AT PR), naming the PR or branch and the evidence location.
```

In "## Divergences and handback", replace the cross-boundary sentence
`Non-interactive transport: hand back
  without asking — stopping is what the wrong-premise interrupt has always required.` with:

```markdown
Non-interactive transport: post the
  premise, evidence, and blast radius as a mailbox `question` and wait on the reply; the
  supervisor may answer continue (record the amendment and proceed) or instruct handback. No
  reply within the wait → hand back exactly as below.
```

In the "On hand back:" list, change step 4's opening from `4. Stop. Tell the operator` to:

```markdown
4. Post `concluded` with `outcome: handback`. Stop. Tell the operator
```

In "## Direction stories", change the final line `- Then stop. Re-entering planning is the operator's move, …` to open with the outcome post:

```markdown
- Post `concluded` with `outcome: dossier`, naming the dossier path. Then stop. Re-entering
  planning is the operator's move, in a fresh planner session — never this session, which sits
  in a story worktree on a stale branch.
```

Append to "## Interrupts — the only three":

```markdown
If an interrupt ends the story, post the terminal `concluded` before stopping: interrupt 1
ends via the handback protocol (`outcome: handback`), interrupt 2 posts `outcome: failed`,
interrupt 3 posts `outcome: blocked`.
```

- [ ] **Step 4: Edit `agent-handoff/SKILL.md`**

In the story-execution template, insert after the `Sprint identity: …` line:

```
Mailbox: {MAILBOX} — post evidence, questions, and your terminal outcome per the contract's Mailbox section.
```

And in the paragraph after the template (the one explaining `{SPRINT}`/`{BRANCH}`), append:

```markdown
`{MAILBOX}` is the literal mail directory — `~/.sprint-mail/<repo-basename>/{SPRINT}/`, with
the repo basename resolved at render time.
```

- [ ] **Step 5: Verify green** — `test/lint-skills.sh` → 0 failed. (`test-wave-handoffs.sh` stays green: the renderer catches up in Task 7, and no existing assertion pins the template's line count.)

- [ ] **Step 6: Commit**

```bash
git add agent-handoff/EXECUTION.md agent-handoff/SKILL.md test/lint-skills.sh
git commit -m "feat(handoff): mailbox contract and terminal outcomes on every exit"
```

---

### Task 5: Supervisor lifecycle in sprint-orchestrator/SKILL.md

**Files:**
- Modify: `sprint-orchestrator/SKILL.md`
- Modify: `test/lint-skills.sh`

**Interfaces:**
- Consumes: `sprint-mail.sh` (Task 1), mailbox contract wording (Task 4 — `The mailbox is never state` must appear here too).
- Produces: `## Point of Contact`, `## Supervising the Wave` section names; the pinned phrases listed in Step 1; "ownership transfer" as a term Task 6 defines.

- [ ] **Step 1: Add lint pins**

```bash
has   "orchestrator: point of contact"          "## Point of Contact" "$ORCH"
has   "orchestrator: supervising section"       "## Supervising the Wave" "$ORCH"
has   "orchestrator: merge-order dispatch constraint" "merge-order-independent" "$ORCH"
has   "orchestrator: trailer-preserving merge"  "must preserve trailers" "$ORCH"
has   "orchestrator: post-merge DONE check"     "after the merge" "$ORCH"
has   "orchestrator: mailbox never state"       "The mailbox is never state" "$ORCH"
has   "orchestrator: rescue bound by contract"  "following EXECUTION.md like any executor" "$ORCH"
has   "orchestrator: planner owns loop call"    "the planner owns it" "$ORCH"
```

- [ ] **Step 2: Run lint — expect those 8 FAILs**

- [ ] **Step 3: Edit `sprint-orchestrator/SKILL.md`**

Replace the intro paragraph (currently `Manual sprint-planning skill for turning raw inputs into independent story handoffs. It plans and hands off; the one sanctioned exception is firing \`loop: direct\` stories as subagents after the user approves the recap (see Executing Direct Stories In-Session). It never implements stories inline and never declares work done.`) with:

```markdown
Manual sprint skill: it plans verified story handoffs, dispatches them, supervises the wave to
conclusion, and integrates the results. In-session execution is sanctioned in exactly two
shapes — firing approved `loop: direct` stories as subagents after the user approves the recap
(see Executing Direct Stories In-Session), and rescuing a problem story under an ownership
transfer (see Supervising the Wave). Everything else is dispatched.
```

Insert after the `## Contract` section:

```markdown
## Point of Contact

The user talks to the orchestrator; executors talk to it through the mailbox. The user enters a
story session only when the plan routed an interactive (`loop: full`) story there. Cross-story
decisions, priority calls, and product questions land here, not in executor threads.
```

In `## Contract`, replace the bullet `- Mutate only sprint planning files and tracker sink calls unless the user asks for more.` with:

```markdown
- Planning writes touch only sprint planning files and tracker sink calls. Integration adds
  exactly two more: merging story branches per the story's execution mode, and rescue commits
  under an ownership transfer — both bound by EXECUTION.md.
```

In `## Plan Session`, replace `\`loop:\` is a judgment call, not a tier rule — ask the user when unsure.` with:

```markdown
`loop:` is a judgment call, not a tier rule — the planner owns it. The recap shows every
story's `loop:` before dispatch, so the user can veto there.
```

Delete the whole `## Integration Is Planned Here, Performed Elsewhere` section (superseded below; the feedback-sweep sentence it carried already lives in Waves Are Planned Incrementally).

Insert, where that section was:

```markdown
## Supervising the Wave

Dispatch is not the end of the session — the wave is supervised to conclusion.

Parallel dispatch is constrained by merge order: under `autonomous`, executors merge
themselves, so fire in parallel only stories that are both ownership-disjoint AND
merge-order-independent. When merge order matters, use `stop-at-pr` (the supervisor merges in
order) or dispatch serially.

While the wave runs, watch the mailbox (`sprint-mail.sh list` / `wait`; a reactive watch where
the harness has one) and sprint status. Answer executor `question`s with the plan's authority;
`note` redirects are legal only while a story has not concluded. The mailbox is never state:
DONE is still both trailers on a trunk-reachable commit, and `sprint-status.sh` never reads
the mailbox.

On each terminal `concluded` outcome, verify before integrating: the diff, the hand-back
evidence, the story's "Done means". Then:

- `stop-at-pr`, verified good → merge it, in `00-overview.md`'s merge order. The merge method
  must preserve trailers — merge commit or rebase; squash only if the squash commit message
  itself carries both trailers. Conflicts: rebase once, retry once, else stop and report. The
  done-check is `sprint-status.sh` reporting `DONE` after the merge — trailers on the feature
  branch are not the check. Then deploy and verify per the project's convention (AGENTS.md),
  and fire `card.done` only after the DONE check passes.
- `autonomous` → the executor already merged; run the same post-merge DONE check on what
  landed. A story that landed without trailers is a defect: dispose of it, or re-dispatch a
  fix under an ownership transfer.
- problems → judgment, in rising order of cost: a mailbox `note` while the story is still
  live; re-dispatch under an ownership transfer; rescue inline — take the story over under an
  ownership transfer and finish it yourself, following EXECUTION.md like any executor:
  trailers on every commit, ownership bounds, single writer per file.
```

In `## Executing Direct Stories In-Session`, replace the bullet `- First failure stops the fleet: report what ran and what failed, leave the failed branch for
  inspection, no automatic retries.` with:

```markdown
- First failure stops the dispatch batch: report what ran and what failed, leave the failed
  branch for inspection, no automatic retries mid-batch. Disposal, re-dispatch, or rescue
  afterwards is the integrate step's judgment (see Supervising the Wave).
```

- [ ] **Step 4: Verify green** — `test/lint-skills.sh` → 0 failed; run the other suites too.

- [ ] **Step 5: Commit**

```bash
git add sprint-orchestrator/SKILL.md test/lint-skills.sh
git commit -m "feat(sprint): supervisor lifecycle — dispatch, supervise, integrate"
```

---

### Task 6: Ownership transfer + resume grant

**Files:**
- Modify: `sprint-orchestrator/SKILL.md` (new `## Ownership Transfer` section, after `## Supervising the Wave`)
- Modify: `agent-handoff/EXECUTION.md` (preflight exception)
- Modify: `agent-handoff/SKILL.md` (takeover render rule)
- Modify: `test/lint-skills.sh`

**Interfaces:**
- Consumes: "ownership transfer" references from Task 5; terminal outcomes from Task 4.
- Produces: the grant line grammar, used verbatim everywhere: `Resume grant: resume designated branch {BRANCH} at {SHA} — {WHAT REMAINS}`.

- [ ] **Step 1: Add lint pins**

```bash
has   "orchestrator: ownership transfer section" "## Ownership Transfer" "$ORCH"
has   "orchestrator: never take over live"       "Never take over a live executor" "$ORCH"
has   "orchestrator: grant grammar"              "resume designated branch" "$ORCH"
has   "contract: resume grant exception"         "resume grant"       "$AHEXEC"
has   "handoff: takeover render rule"            "Resume grant:"      "$AH"
has   "handoff: ordinary kickoffs still refuse"  "Ordinary kickoffs never carry it" "$AH"
```

- [ ] **Step 2: Run lint — expect those 6 FAILs**

- [ ] **Step 3: Edit the three files**

`sprint-orchestrator/SKILL.md`, insert after `## Supervising the Wave`:

```markdown
## Ownership Transfer

Re-dispatch, rescue, and demotion succession operate on a branch that already exists — exactly
what the preflight refuses. Takeover is legal only through this protocol:

- Precondition: the current owner is finished — a terminal `concluded` outcome, or a transport
  confirmed dead (subagent exited; the user closed the session). Never take over a live
  executor.
- Record the transfer: branch, worktree path (if any), HEAD SHA, and what remains to be done.
- The successor's kickoff is a story-execution render carrying an explicit grant line —
  `Resume grant: resume designated branch {BRANCH} at {SHA} — {WHAT REMAINS}` — and the grant
  is the ONLY thing that overrides the branch-exists refusal; a kickoff without one still
  refuses. Inline rescue states the same grant in-session before its first commit.
- Single writer: the grant names exactly one successor; at most one authorized owner at any
  moment.
```

`agent-handoff/EXECUTION.md`, in `## 0. Preflight`, replace the taken-branch bullet
(`- If this story's designated branch — the story doc's exact \`branch:\` value — already exists on
  any ref, the story is taken. STOP and report; never co-opt someone else's branch. Story numbers
  restart every sprint, so a bare \`sprint/{NN}-*\` match false-positives on previous sprints.`) with:

```markdown
- If this story's designated branch — the story doc's exact `branch:` value — already exists on
  any ref, the story is taken. STOP and report; never co-opt someone else's branch. Story numbers
  restart every sprint, so a bare `sprint/{NN}-*` match false-positives on previous sprints.
  Sole exception: your kickoff carries a resume grant naming this exact branch and a HEAD SHA.
  Verify the branch's HEAD matches the grant (mismatch → STOP and report), reuse the branch, and
  continue from the transfer record instead of branching fresh.
```

`agent-handoff/SKILL.md`, append to the story-execution bullet list (after the pre-render claim check bullet):

```markdown
- Takeover kickoffs — re-dispatch or rescue authorized by the supervisor's ownership transfer
  (see `sprint-orchestrator/SKILL.md`) — add one line after `Sprint identity:`:
  `Resume grant: resume designated branch {BRANCH} at {SHA} — {WHAT REMAINS}`. Ordinary
  kickoffs never carry it, and for them the pre-render claim check refusal stands unchanged.
```

- [ ] **Step 4: Verify green** — `test/lint-skills.sh` → 0 failed; other suites green.

- [ ] **Step 5: Commit**

```bash
git add sprint-orchestrator/SKILL.md agent-handoff/EXECUTION.md agent-handoff/SKILL.md test/lint-skills.sh
git commit -m "feat(sprint): ownership transfer protocol with resume grants"
```

---

### Task 7: DISPOSED events + story-scoped event IDs

**Files:**
- Modify: `sprint-orchestrator/SKILL.md` (new `## Disposal Is an Event` section after `## Ownership Transfer`; event-ID scheme in the Waves section)
- Modify: `agent-handoff/EXECUTION.md` (REPLAN/DIRECTION templates gain `{NN}` in IDs; sprint-docs branch name)
- Modify: `sprint-orchestrator/README.md` (event-ID example)
- Modify: `test/lint-skills.sh`

**Interfaces:**
- Produces: event headings `## DISPOSED — dp-YYYYMMDD-NN-<n> — Story NN`, `## REPLAN — rp-YYYYMMDD-{NN}-<n> — Story {NN}`, `## DIRECTION — dr-YYYYMMDD-{NN}-<n> — Story {NN}`; branch scheme `sprint-docs/rp-YYYYMMDD-{NN}-<n>`. (The existing `wave-handoffs.sh` unresolved-event awk keys on fields `$4`/`$7` of the heading — the ID grows but field positions are unchanged, so no script change.)

- [ ] **Step 1: Add lint pins**

```bash
has   "orchestrator: DISPOSED heading"          "## DISPOSED — dp-"  "$ORCH"
has   "orchestrator: disposed is wave accounting" "wave accounting, never DONE" "$ORCH"
has   "orchestrator: story-scoped event ids"    "rp-YYYYMMDD-NN-"    "$ORCH"
has   "contract: story-scoped replan id"        "rp-YYYYMMDD-{NN}-"  "$AHEXEC"
has   "contract: story-scoped direction id"     "dr-YYYYMMDD-{NN}-"  "$AHEXEC"
```

(The existing pins `"## REPLAN — rp-"` / `"## DIRECTION — dr-"` still pass — they are prefixes.)

- [ ] **Step 2: Run lint — expect those 5 FAILs**

- [ ] **Step 3: Edit the files**

`sprint-orchestrator/SKILL.md`, insert after `## Ownership Transfer`:

```markdown
## Disposal Is an Event

A story the wave gives up on — cut, deferred, or reassigned — is recorded as an immutable
DISPOSED event in `STORY-FEEDBACK.md`, same discipline as REPLAN/DIRECTION:

    ## DISPOSED — dp-YYYYMMDD-NN-<n> — Story NN
    - Outcome: cut | deferred | reassigned
    - Cleanup: <branch / worktree / PR disposition>
    - Reason: <one line>

DISPOSED is wave accounting, never DONE: `sprint-status.sh` keeps reporting git truth, and the
next planner treats a DISPOSED story as settled intent, not unfinished work. Event IDs of all
kinds carry the story number — `rp-YYYYMMDD-NN-<n>`, `dr-YYYYMMDD-NN-<n>`, `dp-YYYYMMDD-NN-<n>`
— so parallel writers cannot collide on same-day IDs. Events already recorded keep their old
IDs; events are immutable.
```

In the same file's `## Waves Are Planned Incrementally` section, update the two event-heading
references from `## REPLAN — rp-YYYYMMDD-<n> — Story NN` to `## REPLAN — rp-YYYYMMDD-NN-<n> — Story NN`
and `## DIRECTION — dr-YYYYMMDD-<n> — Story NN` to `## DIRECTION — dr-YYYYMMDD-NN-<n> — Story NN`,
and add `## DISPOSED — dp-YYYYMMDD-NN-<n> — Story NN` to the sweep's list of unresolved-event shapes.

`agent-handoff/EXECUTION.md`:
- REPLAN template heading `## REPLAN — rp-YYYYMMDD-<n> — Story {NN}` → `## REPLAN — rp-YYYYMMDD-{NN}-<n> — Story {NN}`
- `a
   \`sprint-docs/rp-YYYYMMDD-<n>\` branch` → `a
   \`sprint-docs/rp-YYYYMMDD-{NN}-<n>\` branch`
- DIRECTION template heading `## DIRECTION — dr-YYYYMMDD-<n> — Story {NN}` → `## DIRECTION — dr-YYYYMMDD-{NN}-<n> — Story {NN}`
- The events sentence `Events are immutable, carry an id, and are never
   edited afterwards` stays as is.

`sprint-orchestrator/README.md`: `a \`## REPLAN — rp-YYYYMMDD-<n> — Story NN\`
event` → `a \`## REPLAN — rp-YYYYMMDD-NN-<n> — Story NN\`
event`.

- [ ] **Step 4: Verify green** — `test/lint-skills.sh`, `test-wave-handoffs.sh` (its fixture writes `rp-20260601-1`-style IDs — the awk field positions are unchanged, so it still passes; if it fails, the fixture IDs may be updated to `rp-20260601-04-1` but the assertion strings must be updated in the same breath).

- [ ] **Step 5: Commit**

```bash
git add sprint-orchestrator/SKILL.md agent-handoff/EXECUTION.md sprint-orchestrator/README.md test/lint-skills.sh
git commit -m "feat(sprint): DISPOSED events and story-scoped event ids"
```

---

### Task 8: Planner handoff + demotion cutover

**Files:**
- Modify: `sprint-orchestrator/SKILL.md` (new `## The Planner Handoff` section after `## Disposal Is an Event`; wave-boundary sentence + one-planner rule reworded in `## Waves Are Planned Incrementally`)
- Modify: `test/lint-skills.sh`

**Interfaces:**
- Consumes: DISPOSED (Task 7) for the wave-conclusion predicate; mailbox path wording (Task 4).
- Produces: the planner-handoff template and the pinned demotion wording `no longer counts as a planner`.

- [ ] **Step 1: Add lint pins**

```bash
has   "orchestrator: planner handoff section"   "## The Planner Handoff" "$ORCH"
has   "orchestrator: handoff goal spans the wave" "supervised to conclusion" "$ORCH"
has   "orchestrator: demotion cutover"          "no longer counts as a planner" "$ORCH"
hasnt "orchestrator: handoff never asks identity" "identify its model" "$ORCH"
```

(That last pin guards the template: the handoff must not instruct the receiver to identify its model; the phrase must simply never appear as an instruction — keep it out entirely.)

- [ ] **Step 2: Run lint — expect 3 FAILs** (the `hasnt` passes already; it prevents regressions).

- [ ] **Step 3: Edit `sprint-orchestrator/SKILL.md`**

Insert after `## Disposal Is an Event`:

```markdown
## The Planner Handoff

A wave concludes when every story is DONE or DISPOSED. The next wave is never planned in this
transcript — supervision leftovers poison planning focus. Render a planner handoff for a fresh
session, then stop:

    Sprint planning continues: <sprint-basename> — wave <N+1>

    Re-invoke /sprint-orchestrator on <literal sprint path>.
    Wave <N> outcome: <one line per story — merged / disposed / leftover>.
    Leftover in flight: <story NN and who holds it | none>.
    Unresolved events: <ids | none>.
    Mailbox: <literal mailbox path> — sweep it before planning.

    /goal Wave <N+1> planned, dispatched, and supervised to conclusion — every story
    merged or disposed — and the next planner handoff rendered.

The `/goal` targets the NEXT wave boundary — a goal that ends at dispatch would recreate the
plan-and-exit behavior this lifecycle replaces.

**Early unblock.** If only a leftover story holds the wave and nothing in wave N+1 depends on
it, render the planner handoff now and demote yourself: from that moment, answer no mailbox
messages and write no planning files — story docs, `00-overview.md`, and event resolutions
belong to the fresh planner. You act solely as the leftover's executor: executor mailbox kinds,
executor-side events (a REPLAN on handback), nothing more. A demoted supervisor no longer
counts as a planner.
```

In `## Waves Are Planned Incrementally`, replace
`At each wave boundary (the wave's stories read \`DONE\` in \`sprint-status.sh\`), the user re-invokes
this skill on the sprint directory.` with:

```markdown
At each wave boundary (every story `DONE` or DISPOSED), the outgoing supervisor renders the
planner handoff (see The Planner Handoff) and the user pastes it into a fresh session.
```

And replace `One planner per sprint dir at a time: concurrent plan sessions collide on story numbers and
merge order.` with:

```markdown
One planner per sprint dir at a time: concurrent plan sessions collide on story numbers and
merge order. Succession, not exclusion: a demoted supervisor no longer counts as a planner.
```

- [ ] **Step 4: Verify green** — `test/lint-skills.sh` → 0 failed (existing pin `"wave boundary"` still matches the reworded sentence).

- [ ] **Step 5: Commit**

```bash
git add sprint-orchestrator/SKILL.md test/lint-skills.sh
git commit -m "feat(sprint): planner handoff at wave boundaries with demotion cutover"
```

---

### Task 9: Renderer parity — wave-handoffs.sh

**Files:**
- Modify: `sprint-orchestrator/wave-handoffs.sh`
- Modify: `sprint-orchestrator/test/test-wave-handoffs.sh`
- Modify: `test/lint-skills.sh`

**Interfaces:**
- Consumes: the template's Mailbox line (Task 4) — renderer output must match it with values resolved; the dispatch constraint wording (Task 5).

- [ ] **Step 1: Add failing assertions to `sprint-orchestrator/test/test-wave-handoffs.sh`**

After the existing kickoff assertions (`has "kickoff checks exact claim branch" …` block), add:

```bash
has "kickoff renders mailbox line"          "$OUTPUT" "Mailbox: ~/.sprint-mail/"
has "mailbox line names the sprint"         "$OUTPUT" "/$SPRINT_NAME/ — post evidence, questions, and your terminal outcome"
case "$OUTPUT" in
  *"Resume grant:"*) no "ordinary kickoffs carry no resume grant" ;;
  *) ok "ordinary kickoffs carry no resume grant" ;;
esac
case "$OUTPUT" in
  *'These run in parallel'*) no "unconditional parallel sentence removed" ;;
  *) ok "unconditional parallel sentence removed" ;;
esac
has "dispatch constraint rendered"          "$OUTPUT" "merge-order-independent"
```

And in `test/lint-skills.sh`, in the renderer block:

```bash
has   "renderer: mailbox line"               "sprint-mail"        "$WHS"
hasnt "renderer: no unconditional parallel"  "These run in parallel" "$WHS"
```

- [ ] **Step 2: Run both — expect the new assertions to FAIL**

Run: `sprint-orchestrator/test/test-wave-handoffs.sh; test/lint-skills.sh | grep FAIL`

- [ ] **Step 3: Edit `sprint-orchestrator/wave-handoffs.sh`**

After the `sprint_name="$(basename "$sprint_dir")"` line, add:

```bash
# Mailbox path namespaced by repo (worktree-safe); mirrors sprint-mail.sh's derivation.
repo_name="$(git rev-parse --git-common-dir 2>/dev/null)" \
  && repo_name="$(basename "$(dirname "$(cd "$repo_name" && pwd)")")" \
  || repo_name="$(basename "$(pwd)")"
mailbox="~/.sprint-mail/$repo_name/$sprint_name/"
```

Replace the recap's closing line
`printf '\nThese run in parallel; see \`00-overview.md\` for the ownership and merge contract.\n'` with:

```bash
printf '\nStories above are dispatch candidates — fire in parallel only those that are ownership-disjoint\n'
printf 'and merge-order-independent; see `00-overview.md` for ownership and merge order.\n'
```

In the per-story kickoff block, after the `printf 'Sprint identity: …'` line, add:

```bash
printf 'Mailbox: %s — post evidence, questions, and your terminal outcome per the contract'"'"'s Mailbox section.\n' "$mailbox"
```

- [ ] **Step 4: Verify green**

Run: `sprint-orchestrator/test/test-wave-handoffs.sh && test/lint-skills.sh && sprint-orchestrator/test/test-sprint-status.sh && sprint-orchestrator/test/test-sprint-mail.sh`
Expected: all pass, 0 failed.

- [ ] **Step 5: Commit**

```bash
git add sprint-orchestrator/wave-handoffs.sh sprint-orchestrator/test/test-wave-handoffs.sh test/lint-skills.sh
git commit -m "feat(sprint): render mailbox line and dispatch constraint in wave handoffs"
```

---

### Task 10: Documentation sweep + full verification

**Files:**
- Modify: `sprint-orchestrator/README.md`
- Modify: `agent-handoff/README.md`

**Interfaces:** none produced — prose catch-up only. READMEs are not lint-pinned beyond Task 2's checks; keep wording consistent with the SKILL.md sections landed above.

- [ ] **Step 1: Update `sprint-orchestrator/README.md`**

Replace the intro sentence `It plans and hands off. It does not implement stories, merge branches, or
declare work done.` with:

```markdown
It plans, dispatches, supervises the wave to conclusion, and integrates results — merging per
the story's execution mode, disposing of or rescuing problem stories, and handing planning to a
fresh session at each wave boundary. Story state stays derived from git throughout.
```

Replace the wave-checkpoint sentence `Blocked work is deferred — story number allocated and
a stub recorded in the overview — and gets its doc at the wave checkpoint: re-invoke the skill on
the sprint directory when a wave lands, and it reassesses progress before writing the next wave.` with:

```markdown
Blocked work is deferred — story number allocated and a stub recorded in the overview — and
gets its doc at the wave checkpoint: when a wave concludes (every story DONE or DISPOSED), the
outgoing supervisor renders a planner handoff and a fresh session reassesses progress before
writing the next wave.
```

In the "Tests" section, add the new suite to the list:

```markdown
sprint-orchestrator/test/test-sprint-mail.sh   # mailbox helper: sequencing, replies, waits
```

Append a short section after "Render a wave's handoffs":

```markdown
## The mailbox

Executors and the supervising session exchange transient mail in
`~/.sprint-mail/<repo>/<sprint>/` via `sprint-mail.sh` (beside `sprint-status.sh`): executors
post `evidence`, one blocking `question` at a time, and a terminal `concluded` outcome on every
exit; the supervisor posts `reply` and `note`. It is never state — story state stays in the
commit trailers — and when nobody answers, everything degrades to the REPLAN handback protocol.
```

- [ ] **Step 2: Update `agent-handoff/README.md`**

Append to the paragraph ending `hand back to the sprint
planner via a REPLAN event in \`STORY-FEEDBACK.md\`.`:

```markdown
Executors also keep a transient mail lane with the supervising planner
(`~/.sprint-mail/<repo>/<sprint>/`, via `sprint-orchestrator`'s `sprint-mail.sh`): `evidence`
posts, one blocking `question` at a time, and a terminal `concluded` outcome on every exit —
never a substitute for the git-derived state or the event protocol.
```

- [ ] **Step 3: Full verification run**

Run:
```bash
test/lint-skills.sh && \
sprint-orchestrator/test/test-sprint-status.sh && \
sprint-orchestrator/test/test-wave-handoffs.sh && \
sprint-orchestrator/test/test-sprint-mail.sh && \
codex/test/test.sh
```
Expected: every suite reports 0 failed.

- [ ] **Step 4: Commit**

```bash
git add sprint-orchestrator/README.md agent-handoff/README.md
git commit -m "docs: supervisor-era README sweep for sprint skills"
```

---

## Deviations from the spec (intentional, small)

- Spec §6 says rescope the `no unconditional 'do not merge'` lint check. None of the new prose
  uses the lowercase phrase "do not merge", so the blunt check stays — simpler and still
  correct. Rescope only if a future sentence genuinely needs the phrase.
- Spec's `wait` example uses `<dir>` loosely; the implemented interface takes the sprint dir
  and derives the mailbox, same as `post`/`list`.
