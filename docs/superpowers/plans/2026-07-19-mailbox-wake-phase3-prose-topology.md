# Mailbox wake — Phase 3: prose, topology-aware rendering, READMEs

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Wire the rendered `Mailbox wait:` prose to the Phase-2 machinery — a main-session Claude executor/supervisor arms `sprint-mail.sh arm --harness claude` and ends the turn, an in-session subagent renders the non-arming fallback — with the renderer taking topology as a required fail-closed input, and the READMEs/INSTALL.md naming the Claude hook.

**Architecture:** The `Mailbox wait:` selection is harness × topology. Topology is a dispatch-time render input, never story frontmatter (transport is resolved at handoff time): `wave-handoffs.sh` takes a **required** `--topology <main-session|subagent>` argument; `agent-handoff/SKILL.md`'s story-execution mode keys the same selection on target (all four paste targets are main sessions) plus the in-session-subagent dispatch case. Main-session forms arm with `--harness codex|claude` (Phase 2's `arm` refuses without the flag); **subagent topology renders the non-arming fallback on BOTH harnesses**. Rendered-output enforcement lives in `test-wave-handoffs.sh`; static prose pins in `test/lint-skills.sh`.

**Tech Stack:** Bash 3.2, coreutils only. Tests and lint are bash + `grep`.

This is Phase 3 (final) of the spec `docs/superpowers/specs/2026-07-19-unified-mailbox-wake-design.md` (§7). Phases 1–2 are merged to `main` (local, unpushed).

## Conscious deviations from spec §7 (settled at the Codex gate, 2026-07-19, sol/xhigh, two rounds)

1. **The `(codex, subagent)` cell renders the fallback, not arm.** §7's "(codex, \*) arms" contradicts the spec's own Non-goals ("In-session subagent executors do not arm blocking waits" — generic, not Claude-scoped). Resolved toward the Non-goals: a subagent kickoff never arms, either harness. The cell is unreachable in the dispatch model anyway — in-session dispatch of a codex-transport story is `codex exec`, itself a main session.
2. **`--topology` is required, no default.** A defaulted `main-session` would let a forgotten flag silently render an arming kickoff into a subagent, which then stalls at its blocking point without posting `concluded`; the reaper cleans the record, not the broken story. Omission must error before any output.
3. **The subagent pass renders only `loop: direct` stories** and names each skipped story on stderr ("never subagent a `loop: full` story" — `sprint-orchestrator/SKILL.md`). Zero direct stories → exit 2.
4. **The spec's "lint pin" for rendered output is homed in `test-wave-handoffs.sh`** (fixtures exist there; `test/lint-skills.sh` is grep-on-static-files by repo convention). Lint pins the static renderer/prose strings.

## Global Constraints

- **Bash 3.2, coreutils only.** No `jq`, no GNU-only flags.
- **Phase 3 is prose + rendering + docs only.** Do NOT touch `sprint-mail.sh`, either hook body, either installer, or `.codex-waits/` naming.
- **Lint pins land in the SAME commit as the pinned prose/code.** No separate lint commit.
- **Every rendered `arm` carries `--harness codex|claude`** — Phase 2's `arm` refuses without it, so any rendered command missing it is a broken instruction.
- **Budgets (spec §6):** supervisor idle wait on Codex stays `1800` (hook timeout 1860); on Claude it is `10800` (hook timeout 10860). Targeted reply waits keep `1800` on both.
- **The fallback wording** everywhere derives from the existing contract phrase: "do not pretend to wait — treat it as no reply and take the fallback path now."
- **Surgical scope:** the pre-existing `driver_hint: either` → claude-contract-path wart in the renderer is out of scope (late harness binding is the vetted design); do not fix it here.
- **Every commit** ends with the standard `Co-Authored-By:` and `Claude-Session:` trailers.

---

### Task 0: Branch + plan doc

**Files:**
- Create: `docs/superpowers/plans/2026-07-19-mailbox-wake-phase3-prose-topology.md` (this file)

- [ ] **Step 1: Fresh branch off main, commit the plan**

```bash
git branch --show-current && git status --short
git switch -c feat/mailbox-wake-phase3 main
git add docs/superpowers/plans/2026-07-19-mailbox-wake-phase3-prose-topology.md
git commit -m "docs: Phase 3 plan — prose, topology-aware rendering, READMEs"
# (append the standard Co-Authored-By / Claude-Session trailers)
```

---

### Task 1: agent-handoff prose — the harness × topology `Mailbox wait:` contract

The skill file is the source of truth for the kickoff shape; the renderer (Task 2) mirrors it.

**Files:**
- Modify: `agent-handoff/SKILL.md` (the Mailbox-wait resolution bullet ~line 156; the template's `Mailbox wait:` line ~177)
- Modify: `agent-handoff/EXECUTION.md` (the Mailbox section's transport branches ~lines 131–139)
- Modify: `test/lint-skills.sh` (same commit)

**Interfaces:**
- Produces: the three canonical `Mailbox wait:` forms (codex main / claude main / subagent fallback) that Task 2's renderer and Task 3's supervisor prose must match verbatim in their command substrings:
  - `arm --harness codex {SPRINT_DIR} {NN}-{SSS}-reply.md 1800` … `END YOUR TURN`
  - `arm --harness claude {SPRINT_DIR} {NN}-{SSS}-reply.md 1800` … `END YOUR TURN`
  - `you are an in-session subagent — the Stop hook never fires for you, so you cannot end your turn and be woken. Do not pretend to wait: if you post a blocking question, treat it as no reply and take the contract's fallback path now.`

- [ ] **Step 1: Flip the lint pins first (they are the failing test)**

In `test/lint-skills.sh`, change:

```bash
has   "handoff: codex wait form is arm-and-end-turn" "arm {SPRINT_DIR} {NN}-{SSS}-reply.md 1800" "$AH"
```
to:
```bash
has   "handoff: codex wait form is arm-and-end-turn" "arm --harness codex {SPRINT_DIR} {NN}-{SSS}-reply.md 1800" "$AH"
has   "handoff: claude wait form is arm-and-end-turn" "arm --harness claude {SPRINT_DIR} {NN}-{SSS}-reply.md 1800" "$AH"
has   "handoff: subagent renders non-arming fallback" "Do not pretend to wait" "$AH"
has   "handoff: mis-scoped direct story note" "re-planned as a main-session story" "$AH"
hasnt "handoff: no background-task wait"     "as a background task" "$AH"
```

And change:

```bash
has   "contract: codex arm wait"             "sprint-mail.sh arm <sprint-dir> {NN}-{SSS}-reply.md 1800" "$AHEXEC"
```
to:
```bash
has   "contract: codex arm wait"             "sprint-mail.sh arm --harness codex <sprint-dir> {NN}-{SSS}-reply.md 1800" "$AHEXEC"
has   "contract: claude main-session arm wait" "sprint-mail.sh arm --harness claude <sprint-dir> {NN}-{SSS}-reply.md 1800" "$AHEXEC"
has   "contract: subagent never arms"        "the Stop hook never fires for a subagent" "$AHEXEC"
hasnt "contract: no background-task wait"    "as a background task" "$AHEXEC"
```

- [ ] **Step 2: Run the lint to verify the new pins fail**

Run: `test/lint-skills.sh`
Expected: FAIL — the six new/changed pins miss (old strings still in both files).

- [ ] **Step 3: Rewrite the `Mailbox wait:` resolution bullet in `agent-handoff/SKILL.md`**

Replace:

```
- The `Mailbox wait:` line resolves the same way, so the executor's comms are settled before
  the story starts: Codex targets render the arm-and-end-turn form (the Stop hook owns the
  wait); Claude targets render the background-task form. `{SPRINT_DIR}` is the literal sprint
  directory path; `{SSS}` stays literal — it is the question's runtime sequence number.
```

with:

```
- The `Mailbox wait:` line resolves on harness × topology, so the executor's comms are
  settled before the story starts. Every paste target is a main session: Codex targets render
  the codex arm-and-end-turn form, Claude targets (claude-cli, claude-session) render the
  claude arm-and-end-turn form (`arm --harness claude …`). An in-session subagent dispatch
  (allowed for `loop: direct` only) renders the non-arming fallback instead, on either
  harness — the Stop hook never fires for a subagent, so it must not pretend to wait; a
  `direct` story that genuinely needs a blocking reply is mis-scoped and must be re-planned
  as a main-session story. `{SPRINT_DIR}` is the literal sprint directory path; `{SSS}` stays
  literal — it is the question's runtime sequence number.
```

- [ ] **Step 4: Rewrite the template's `Mailbox wait:` line in `agent-handoff/SKILL.md`**

Replace (one long line inside the fenced template):

```
Mailbox wait: {post your question, then `~/.codex/skills/sprint-orchestrator/sprint-mail.sh arm {SPRINT_DIR} {NN}-{SSS}-reply.md 1800` (SSS = your question's sequence) and END YOUR TURN — the armed Stop hook wakes you on the reply; never poll or background the wait. | post your question, then run `~/.claude/skills/sprint-orchestrator/sprint-mail.sh wait {SPRINT_DIR} {NN}-{SSS}-reply.md 1800` (SSS = your question's sequence) as a background task — its completion notification is your wake.}
```

with:

```
Mailbox wait: {post your question, then `~/.codex/skills/sprint-orchestrator/sprint-mail.sh arm --harness codex {SPRINT_DIR} {NN}-{SSS}-reply.md 1800` (SSS = your question's sequence) and END YOUR TURN — the armed Stop hook wakes you on the reply; never poll or background the wait. | post your question, then `~/.claude/skills/sprint-orchestrator/sprint-mail.sh arm --harness claude {SPRINT_DIR} {NN}-{SSS}-reply.md 1800` (SSS = your question's sequence) and END YOUR TURN — the armed Stop hook wakes you on the reply; never poll or background the wait. | you are an in-session subagent — the Stop hook never fires for you, so you cannot end your turn and be woken. Do not pretend to wait: if you post a blocking question, treat it as no reply and take the contract's fallback path now.}
```

- [ ] **Step 5: Rewrite the transport branches in `agent-handoff/EXECUTION.md`**

In the Mailbox section, replace the three bullets:

```
  - Codex (Desktop or exec) with the sprint Stop hook installed:
    `sprint-mail.sh arm <sprint-dir> {NN}-{SSS}-reply.md 1800`, then END YOUR TURN with a
    one-line status. The armed hook holds the turn and wakes you when the reply lands or the
    wait times out. Arming and ending the turn IS the wait — never poll, never run `wait`
    under `nohup`/`&`/tmux, never hand-poll in later commands.
  - Claude: run `sprint-mail.sh wait <sprint-dir> {NN}-{SSS}-reply.md 1800` as a background
    task; its completion notification is your wake.
  - Neither available: do not pretend to wait — treat it as no reply and take the fallback
    path now.
```

with:

```
  - Codex (Desktop or exec) with the sprint Stop hook installed:
    `sprint-mail.sh arm --harness codex <sprint-dir> {NN}-{SSS}-reply.md 1800`, then END
    YOUR TURN with a one-line status. The armed hook holds the turn and wakes you when the
    reply lands or the wait times out. Arming and ending the turn IS the wait — never poll,
    never run `wait` under `nohup`/`&`/tmux, never hand-poll in later commands.
  - Claude, MAIN session only, with the sprint Stop hook installed (install-claude-hook.sh):
    `sprint-mail.sh arm --harness claude <sprint-dir> {NN}-{SSS}-reply.md 1800`, then END
    YOUR TURN with a one-line status — same semantics as the Codex form.
  - An in-session subagent (either harness — the Stop hook never fires for a subagent, so
    you cannot end your turn and be woken), or neither hook available: do not pretend to
    wait — treat it as no reply and take the fallback path now.
```

- [ ] **Step 6: Run the lint to verify it passes**

Run: `test/lint-skills.sh`
Expected: PASS — all pins green, including the surviving `contract: arming is the wait` and `contract: orphaned waits banned` pins.

- [ ] **Step 7: Commit**

```bash
git branch --show-current && git status --short
git add agent-handoff/SKILL.md agent-handoff/EXECUTION.md test/lint-skills.sh
git commit -m "feat(sprint): Mailbox wait resolves on harness x topology"
# (append the standard Co-Authored-By / Claude-Session trailers)
```

---

### Task 2: `wave-handoffs.sh` — required `--topology`, subagent fallback, `--harness` in both arm forms

**Files:**
- Modify: `sprint-orchestrator/wave-handoffs.sh` (usage/arg parse ~lines 3–25; doc collection ~93–103; sheet header ~118–124; mailwait `case "$driver_hint"` ~166–171)
- Test: `sprint-orchestrator/test/test-wave-handoffs.sh`
- Modify: `test/lint-skills.sh` (renderer pins — same commit)

**Interfaces:**
- Consumes: the three canonical forms from Task 1 (verbatim command substrings).
- Produces: `wave-handoffs.sh <sprint-dir> <wave> --topology <main-session|subagent>`; exit 2 on missing/invalid topology, and on a subagent pass with zero `loop: direct` stories.

- [ ] **Step 1: Update the render test (the failing test first)**

In `sprint-orchestrator/test/test-wave-handoffs.sh`:

(a) Add a wave-3 fixture story after the story 22 line (used by the zero-direct case):

```bash
story 30 full-only-w3   'wave: 3' 'driver_hint: claude' 'tier: B' 'tier_why: fixture' 'loop: full'
```

(b) Change the main render invocation (line ~40) to:

```bash
OUTPUT="$("$WH" "$SPRINT" 1 --topology main-session 2>&1)" && ok "wave-handoffs runs" || { no "wave-handoffs runs"; printf '%s\n' "$OUTPUT"; }
```

(c) Replace the two `Mailbox wait` pins:

```bash
has "codex story renders arm wait line"     "$OUTPUT" "Mailbox wait: post your question, then \`~/.codex/skills/sprint-orchestrator/sprint-mail.sh arm $SPRINT 07-{SSS}-reply.md 1800\`"
has "codex arm line ends the turn"          "$OUTPUT" "END YOUR TURN — the armed Stop hook wakes you on the reply"
has "claude story renders background wait"  "$OUTPUT" "\`~/.claude/skills/sprint-orchestrator/sprint-mail.sh wait $SPRINT 08-{SSS}-reply.md 1800\` (SSS = your question's sequence) as a background task"
```

with:

```bash
has "codex story renders arm wait line"     "$OUTPUT" "Mailbox wait: post your question, then \`~/.codex/skills/sprint-orchestrator/sprint-mail.sh arm --harness codex $SPRINT 07-{SSS}-reply.md 1800\`"
has "codex arm line ends the turn"          "$OUTPUT" "END YOUR TURN — the armed Stop hook wakes you on the reply"
has "claude story renders arm wait line"    "$OUTPUT" "\`~/.claude/skills/sprint-orchestrator/sprint-mail.sh arm --harness claude $SPRINT 08-{SSS}-reply.md 1800\`"
case "$OUTPUT" in
  *'as a background task'*) no "no background-task wait rendered" ;;
  *) ok "no background-task wait rendered" ;;
esac
```

(d) After the claim-branch/mailbox assertions (before the feedback-events section), add the topology block:

```bash
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
```

(e) Add `--topology main-session` to the two feedback-events invocations:

```bash
WOUT="$("$WH" "$SPRINT" 1 --topology main-session 2>"$WERR")"
```
and
```bash
"$WH" "$SPRINT" 1 --topology main-session >/dev/null 2>"$RERR"
```

- [ ] **Step 2: Run the render test to verify it fails**

Run: `sprint-orchestrator/test/test-wave-handoffs.sh`
Expected: FAIL — the script accepts the old 2-arg form (missing-topology case fails), renders the old codex/claude wait forms, and knows no subagent pass.

- [ ] **Step 3: Implement in `wave-handoffs.sh`**

(a) Replace the arg parse:

```bash
sprint_dir="${1:-}"
wave="${2:-}"
[ -n "$sprint_dir" ] && [ -n "$wave" ] \
  || { echo "wave-handoffs: usage: wave-handoffs.sh docs/sprints/<sprint> <wave>" >&2; exit 2; }
```

with:

```bash
sprint_dir="${1:-}"
wave="${2:-}"
usage="wave-handoffs: usage: wave-handoffs.sh docs/sprints/<sprint> <wave> --topology <main-session|subagent>"
# Topology is a dispatch-time render input, never story frontmatter — the operator's paste
# sheet is always main-session; only the orchestrator's own in-session subagent dispatch
# renders the subagent form. Required and fail-closed: an omitted topology must error here,
# not silently render an arming kickoff a subagent could never be woken from.
[ $# -eq 4 ] && [ -n "$sprint_dir" ] && [ -n "$wave" ] && [ "${3:-}" = "--topology" ] \
  || { echo "$usage" >&2; exit 2; }
topology="$4"
case "$topology" in
  main-session|subagent) ;;
  *) echo "$usage" >&2; exit 2 ;;
esac
```

Also update the header comment's synopsis line to `wave-handoffs.sh docs/sprints/<sprint> <wave> --topology <main-session|subagent>` and the example at the bottom of the header comment to carry `--topology main-session`.

(b) In the doc-collection loop, after `[ "$(fm_get "$doc" wave)" = "$wave" ] || continue`, add:

```bash
  # Never subagent a non-direct story (loop: full needs an interactive session).
  if [ "$topology" = "subagent" ] && [ "$(fm_get "$doc" loop)" != "direct" ]; then
    printf 'wave-handoffs: skipping %s — loop: %s never runs as an in-session subagent; render it main-session\n' \
      "$(basename "$doc")" "$(fm_get "$doc" loop)" >&2
    continue
  fi
```

(c) Replace the empty-docs guard:

```bash
[ "${#docs[@]}" -gt 0 ] \
  || { echo "wave-handoffs: no story docs with 'wave: $wave' in $sprint_dir" >&2; exit 2; }
```

with:

```bash
if [ "${#docs[@]}" -eq 0 ]; then
  if [ "$topology" = "subagent" ]; then
    echo "wave-handoffs: no story docs with 'wave: $wave' in $sprint_dir — the subagent pass renders only 'loop: direct' stories" >&2
  else
    echo "wave-handoffs: no story docs with 'wave: $wave' in $sprint_dir" >&2
  fi
  exit 2
fi
```

(d) Replace the sheet-header sentence block:

```bash
printf '_Generated by `wave-handoffs.sh` from the story docs. Each fenced block below is a ready-to-paste '
printf '`agent-handoff` (story-execution) kickoff — paste each into its own executor session. The **Launch** line above '
```

with:

```bash
if [ "$topology" = "subagent" ]; then
  printf '_Generated by `wave-handoffs.sh` from the story docs. Each fenced block below is a story-execution '
  printf 'kickoff for an in-session subagent (`loop: direct` stories only; skipped stories are named on stderr). '
  printf 'Subagent kickoffs render the non-arming `Mailbox wait:` — a subagent cannot end its turn and be woken. The **Launch** line above '
else
  printf '_Generated by `wave-handoffs.sh` from the story docs. Each fenced block below is a ready-to-paste '
  printf '`agent-handoff` (story-execution) kickoff — paste each into its own executor session. The **Launch** line above '
fi
```

(e) Replace the mailwait `case`:

```bash
  case "$driver_hint" in
    codex) contract="~/.codex/skills/agent-handoff/EXECUTION.md"
           mailwait='post your question, then `~/.codex/skills/sprint-orchestrator/sprint-mail.sh arm '"$sprint_dir $story"'-{SSS}-reply.md 1800` (SSS = your question'"'"'s sequence) and END YOUR TURN — the armed Stop hook wakes you on the reply; never poll or background the wait.' ;;
    *)     contract="~/.claude/skills/agent-handoff/EXECUTION.md"
           mailwait='post your question, then run `~/.claude/skills/sprint-orchestrator/sprint-mail.sh wait '"$sprint_dir $story"'-{SSS}-reply.md 1800` (SSS = your question'"'"'s sequence) as a background task — its completion notification is your wake.' ;;
  esac
```

with:

```bash
  case "$driver_hint" in
    codex) contract="~/.codex/skills/agent-handoff/EXECUTION.md"
           mailwait='post your question, then `~/.codex/skills/sprint-orchestrator/sprint-mail.sh arm --harness codex '"$sprint_dir $story"'-{SSS}-reply.md 1800` (SSS = your question'"'"'s sequence) and END YOUR TURN — the armed Stop hook wakes you on the reply; never poll or background the wait.' ;;
    *)     contract="~/.claude/skills/agent-handoff/EXECUTION.md"
           mailwait='post your question, then `~/.claude/skills/sprint-orchestrator/sprint-mail.sh arm --harness claude '"$sprint_dir $story"'-{SSS}-reply.md 1800` (SSS = your question'"'"'s sequence) and END YOUR TURN — the armed Stop hook wakes you on the reply; never poll or background the wait.' ;;
  esac
  # Subagent topology overrides both harness forms: the Stop hook never fires for an
  # in-session subagent, so an armed wait would never wake it — never render an arm here.
  if [ "$topology" = "subagent" ]; then
    mailwait='you are an in-session subagent — the Stop hook never fires for you, so you cannot end your turn and be woken. Do not pretend to wait: if you post a blocking question, treat it as no reply and take the contract'"'"'s fallback path now.'
  fi
```

- [ ] **Step 4: Run the render test to verify it passes**

Run: `sprint-orchestrator/test/test-wave-handoffs.sh`
Expected: PASS — `N passed, 0 failed`.

- [ ] **Step 5: Add the renderer lint pins (same commit)**

In `test/lint-skills.sh`, in the `wave-handoffs.sh` block (after the `renderer: codex wait arms the hook` pin), add:

```bash
has   "renderer: codex arm carries --harness"   "arm --harness codex" "$WHS"
has   "renderer: claude arm carries --harness"  "arm --harness claude" "$WHS"
has   "renderer: subagent fallback form"        "Do not pretend to wait" "$WHS"
has   "renderer: topology is a required input"  "--topology <main-session|subagent>" "$WHS"
hasnt "renderer: no background-task wait"       "as a background task" "$WHS"
```

- [ ] **Step 6: Run lint + render test**

Run: `test/lint-skills.sh && sprint-orchestrator/test/test-wave-handoffs.sh`
Expected: both PASS.

- [ ] **Step 7: Commit**

```bash
git branch --show-current && git status --short
git add sprint-orchestrator/wave-handoffs.sh sprint-orchestrator/test/test-wave-handoffs.sh test/lint-skills.sh
git commit -m "feat(sprint): topology-aware wave kickoffs, arm --harness forms"
# (append the standard Co-Authored-By / Claude-Session trailers)
```

---

### Task 3: `sprint-orchestrator/SKILL.md` — supervisor re-arm + subagent dispatch rule

**Files:**
- Modify: `sprint-orchestrator/SKILL.md` (Supervising the Wave, the re-arm sentence ~lines 206–212; Executing Direct Stories In-Session, after the transport bullet ~line 191)
- Modify: `test/lint-skills.sh` (same commit)

**Interfaces:**
- Consumes: the arm forms from Task 1; the `--topology` flag from Task 2.

- [ ] **Step 1: Add the lint pins first**

In `test/lint-skills.sh`, after `has "orchestrator: supervisor arm globs" ...`, add:

```bash
has   "orchestrator: codex re-arm carries --harness"  "arm --harness codex <sprint-dir> '*-question.md *-concluded.md' 1800" "$ORCH"
has   "orchestrator: claude re-arm at idle budget"    "arm --harness claude <sprint-dir> '*-question.md *-concluded.md' 10800" "$ORCH"
has   "orchestrator: supervisor is a main session"    "the supervisor is always a main session" "$ORCH"
has   "orchestrator: subagent kickoffs render subagent topology" "--topology subagent" "$ORCH"
hasnt "orchestrator: no background-task wait"         "as a background task" "$ORCH"
```

- [ ] **Step 2: Run the lint to verify the new pins fail**

Run: `test/lint-skills.sh`
Expected: FAIL on the five new pins.

- [ ] **Step 3: Rewrite the supervisor re-arm sentence**

In `sprint-orchestrator/SKILL.md` (Supervising the Wave), replace:

```
Then re-arm as an
idle nudge and end the turn — on Codex with the sprint Stop hook installed:
`sprint-mail.sh arm <sprint-dir> '*-question.md *-concluded.md' 1800`, and the hook wakes you on
new mail or timeout; on Claude: run `sprint-mail.sh wait` as a background task. Re-arm on each
wake until the wave concludes — a spurious wake finds nothing unread, a missed wake is caught by
the next sweep.
```

with:

```
Then re-arm as an
idle nudge and end the turn — the supervisor is always a main session, so both harnesses arm
their sprint Stop hook: on Codex
`sprint-mail.sh arm --harness codex <sprint-dir> '*-question.md *-concluded.md' 1800`; on
Claude `sprint-mail.sh arm --harness claude <sprint-dir> '*-question.md *-concluded.md' 10800`
— the idle-wait default under the installed hook's 10860s timeout; targeted reply waits keep
1800. The hook wakes you on new mail or timeout. Re-arm on each
wake until the wave concludes — a spurious wake finds nothing unread, a missed wake is caught by
the next sweep.
```

- [ ] **Step 4: Add the subagent-dispatch rendering rule**

In Executing Direct Stories In-Session, after the bullet ending `their evidence path
ends in Codex.app visual validation.`, add:

```
- Kickoffs fired as in-session subagents are rendered with the subagent topology
  (`wave-handoffs.sh <sprint-dir> <wave> --topology subagent`): a subagent never arms a
  blocking mailbox wait — the Stop hook never fires for it, on either harness — so its
  `Mailbox wait:` is the non-arming fallback. Only main sessions arm; in-session dispatch of
  a codex-transport story is `codex exec`, itself a main session. The operator's paste sheet
  renders with `--topology main-session`.
```

- [ ] **Step 5: Run the lint to verify it passes**

Run: `test/lint-skills.sh`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git branch --show-current && git status --short
git add sprint-orchestrator/SKILL.md test/lint-skills.sh
git commit -m "feat(sprint): supervisor re-arms per harness at the idle budget"
# (append the standard Co-Authored-By / Claude-Session trailers)
```

---

### Task 4: READMEs + INSTALL.md — name the Claude hook

**Files:**
- Modify: `sprint-orchestrator/README.md` (codex-section arm line ~150; new Claude section after the Codex section; wave-handoffs section ~114–133; Tests section ~218–226; the since-epoch comment ~224)
- Modify: `README.md` (root, the machine-setup paragraph ~lines 71–76)
- Modify: `INSTALL.md` (step 2 sprint-orchestrator bullet; step 3 suite list; step 4 report line)
- Modify: `test/lint-skills.sh` (same commit)

- [ ] **Step 1: Add the lint pins first**

In `test/lint-skills.sh`, after `has "sprint readme: names the installer" ...`, add:

```bash
has   "sprint readme: names the claude installer" "install-claude-hook.sh" "$ORCH_README"
has   "sprint readme: codex arm carries --harness" "arm --harness codex" "$ORCH_README"
has   "sprint readme: claude arm carries --harness" "arm --harness claude" "$ORCH_README"
has   "sprint readme: parallel-hook note"       "holds the Stop event's completion" "$ORCH_README"
has   "sprint readme: claude budget note"       "timeout: 10860" "$ORCH_README"
has   "sprint readme: topology flag documented" "--topology" "$ORCH_README"
hasnt "sprint readme: no epoch mentions"        "epoch" "$ORCH_README"
```

After `has "repo readme: names the hook setup" ...`:

```bash
has   "repo readme: names the claude hook setup" "install-claude-hook.sh" "$HERE/../README.md"
```

After `has "install guide: wires the codex hook" ...`:

```bash
has   "install guide: wires the claude hook"    "install-claude-hook.sh" "$INSTALL"
has   "install guide: runs the claude hook suite" "test-claude-stop-wait.sh" "$INSTALL"
has   "install guide: runs the claude installer suite" "test-install-claude-hook.sh" "$INSTALL"
```

- [ ] **Step 2: Run the lint to verify the new pins fail**

Run: `test/lint-skills.sh`
Expected: FAIL on the eleven new pins.

- [ ] **Step 3: Update `sprint-orchestrator/README.md`**

(a) In "Reactive waits on Codex", change the arm command to carry the harness:

```
`sprint-mail.sh arm --harness codex <sprint-dir> <reply-file-or-globs> 1800`, and ends its turn; the hook holds
```

(b) After the Codex section (before "## The rule that makes it work"), add:

```markdown
### Reactive waits on Claude — one-time install (main sessions)

A main-session Claude supervisor or executor waits the same way — arm and end the turn — via
the `claude-stop-wait.sh` Stop hook (its body is kept byte-identical to the Codex hook by a
lint diff pin): the session posts its question or watch globs, runs
`sprint-mail.sh arm --harness claude <sprint-dir> <reply-file-or-globs> [<timeout>]`, and ends
its turn; the hook holds the ending turn until matching unread mail lands or the budget
elapses. Main sessions only: the hook is wired for `Stop`, never `SubagentStop` — an
in-session subagent cannot end its turn and be woken, so rendered subagent kickoffs carry the
non-arming fallback instead of an `arm`.

Once per machine:

```bash
~/claude-skills/sprint-orchestrator/install-claude-hook.sh
```

Idempotent: it appends the hook as its own `Stop` group in `~/.claude/settings.json`
(re-pointing it if the clone moved) and preserves co-installed Stop hooks — an existing
iTerm-status hook survives untouched. No trust dance: Claude settings-json hooks activate on
write (running sessions pick up the edit; a restart is the fallback). Honest limit: a settings
reference is not proof the hook runs — `disableAllHooks` or managed policy can suppress it,
and the installer reports that instead of working around it.

Budget: the hook entry carries `timeout: 10860` — the 3h idle-wait budget (`arm … 10800`)
plus 60s slack, mirroring Codex's 1800/1860 — and targeted reply waits keep `1800`. While a
parked hook waits, it holds the Stop event's completion; co-installed Stop hooks (the iTerm
status hook) still run — the only cost is that the event finishes when the wait does.
```

(c) In "Render a wave's handoffs", change the example to:

```bash
~/.claude/skills/sprint-orchestrator/wave-handoffs.sh docs/sprints/<sprint> 4 --topology main-session > ~/.handoffs/<sprint>-wave4.md
```

and after the "If `STORY-FEEDBACK.md` carries unresolved…" paragraph, add:

```
`--topology` is required: `main-session` renders the paste sheet (every paste target is a
fresh main session); `subagent` renders kickoffs the orchestrator fires as in-session
subagents — those carry the non-arming `Mailbox wait:` (a subagent cannot end its turn and be
woken), and only `loop: direct` stories render, with skips named on stderr.
```

(d) In Tests, change the codex-stop-wait comment and add the two Claude suites:

```bash
sprint-orchestrator/test/test-codex-stop-wait.sh # Codex Stop hook: wake, timeout, cursor + legacy records
sprint-orchestrator/test/test-claude-stop-wait.sh # Claude Stop hook: same records, same wakes
sprint-orchestrator/test/test-install-claude-hook.sh # Claude installer: parity, preserves co-installed hooks
```

(e) Grep the file for any remaining `epoch` and remove it (the lint's `hasnt` enforces this).

- [ ] **Step 4: Update root `README.md`**

Replace:

```
and `sprint-orchestrator/` needs its Codex Stop hook wired once per machine: run
`sprint-orchestrator/install-codex-hook.sh` (details in
[`sprint-orchestrator/README.md`](sprint-orchestrator/README.md), "Reactive waits on Codex").
```

with:

```
and `sprint-orchestrator/` needs its per-harness mailbox Stop hooks wired once per machine:
`sprint-orchestrator/install-codex-hook.sh` (Codex) and
`sprint-orchestrator/install-claude-hook.sh` (Claude) — details in
[`sprint-orchestrator/README.md`](sprint-orchestrator/README.md), "Reactive waits on Codex" /
"Reactive waits on Claude".
```

- [ ] **Step 5: Update `INSTALL.md`**

(a) Replace the sprint-orchestrator bullet in step 2 with:

```markdown
- **sprint-orchestrator** — wire each present harness's mailbox Stop hook, once per machine.
  - Codex present:

    ```bash
    ./sprint-orchestrator/install-codex-hook.sh
    ```

    Verify: it prints `done — hook wired and trusted.` Idempotent — safe to re-run, and it
    re-points the entry if the clone ever moves. This step is not optional on Codex machines:
    untrusted hooks are skipped **silently**, and `sprint-mail.sh arm` refuses to arm until the
    hook is wired. Details and the manual fallback:
    [`sprint-orchestrator/README.md`](sprint-orchestrator/README.md), "Reactive waits on Codex".
  - Claude Code present:

    ```bash
    ./sprint-orchestrator/install-claude-hook.sh
    ```

    Verify: it prints `done — hook wired in` naming the settings file, and any co-installed
    Stop hooks are still present in `~/.claude/settings.json`. Idempotent — safe to re-run,
    re-points if the clone moved. No trust step: Claude settings-json hooks activate on
    write. If the installer warns that hooks are disabled (`disableAllHooks` / managed
    policy), report it. Details:
    [`sprint-orchestrator/README.md`](sprint-orchestrator/README.md), "Reactive waits on Claude".
```

(b) In step 3, extend the suite list to all nine:

```bash
test/lint-skills.sh
codex/test/test.sh
sprint-orchestrator/test/test-sprint-status.sh
sprint-orchestrator/test/test-sprint-mail.sh
sprint-orchestrator/test/test-codex-stop-wait.sh
sprint-orchestrator/test/test-claude-stop-wait.sh
sprint-orchestrator/test/test-install-codex-hook.sh
sprint-orchestrator/test/test-install-claude-hook.sh
sprint-orchestrator/test/test-wave-handoffs.sh
```

(c) In step 4, change the report line to:

```
Tell the user in one short list: which harnesses were linked, whether each present harness's
mailbox Stop hook is wired (Codex: wired **and trusted**; Claude: wired, plus any
disabled-hooks warning), any missing prerequisites (for example a codex CLI that is not
authenticated), and the test tally. Skills appear in each harness's list on its **next**
session — `/agent-handoff` in Claude Code, `$agent-handoff` in Codex.
```

- [ ] **Step 6: Run the lint to verify it passes**

Run: `test/lint-skills.sh`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git branch --show-current && git status --short
git add sprint-orchestrator/README.md README.md INSTALL.md test/lint-skills.sh
git commit -m "docs(sprint): READMEs and INSTALL name the Claude hook"
# (append the standard Co-Authored-By / Claude-Session trailers)
```

---

### Task 5: Full suite + finish the branch

**Files:** none (verification + integration).

- [ ] **Step 1: Run every suite from a clean tree**

```bash
test/lint-skills.sh
sprint-orchestrator/test/test-sprint-mail.sh
sprint-orchestrator/test/test-codex-stop-wait.sh
sprint-orchestrator/test/test-claude-stop-wait.sh
sprint-orchestrator/test/test-install-claude-hook.sh
sprint-orchestrator/test/test-install-codex-hook.sh
sprint-orchestrator/test/test-sprint-status.sh
sprint-orchestrator/test/test-wave-handoffs.sh
codex/test/test.sh
```

Expected: all nine end `N passed, 0 failed`. Any failure → fix before finishing.

- [ ] **Step 2: Finish the development branch**

Use `superpowers:finishing-a-development-branch` — merge to `main` locally, unpushed, mirroring Phases 1 & 2.

---

## Notes for the executor

- **Do NOT touch Phase-1/2 machinery:** `sprint-mail.sh`, `codex-stop-wait.sh`, `claude-stop-wait.sh`, either installer, or the `.codex-waits/` name.
- **Task 1 before Task 2:** `agent-handoff/SKILL.md` is the source of truth for the kickoff shape; the renderer mirrors it. Task 3 and 4 can follow in any order after 2, but keep the commits as sliced.
- The fixture `story()` helper prints extra frontmatter lines BEFORE the defaults and `fm_get` takes the first match, so `'wave: 3'` as an extra line overrides the default `wave: 1`.
- The `hasnt "sprint readme: no epoch mentions"` pin is deliberately broad — the README must end up with zero occurrences of `epoch`.
- The pre-existing renderer wart (a `driver_hint: either` story renders the Claude contract path in the fence while the Launch line offers both cells) is known, out of scope, and must not be "fixed" in passing.
