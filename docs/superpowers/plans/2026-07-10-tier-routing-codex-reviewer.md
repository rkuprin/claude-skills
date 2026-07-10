# Tier Routing — Codex Reviewer Cost Routing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The codex reviewer skill routes each run to a lane — contained → `gpt-5.6-terra` @ `xhigh`, premise-critical → `gpt-5.6-sol` @ `xhigh` — instead of always burning Sol, passing `--model` and `--effort` explicitly on run and resume.

**Architecture:** Lane selection is LLM judgment in `codex/SKILL.md` step 1 (with explicit precedence); the transport wrapper `run-codex.sh` only changes its fallback default (`effort="xhigh"`) and usage text. Wrapper behavior is pinned by the existing fake-codex test harness; lane classification is pinned by a named manual acceptance scenario (grep cannot test LLM judgment).

**Tech Stack:** Markdown skill prose, bash wrapper + bash/grep tests.

**Spec:** `docs/superpowers/specs/2026-07-10-model-tier-routing-design.md`

## Global Constraints

- Repo: `~/claude-skills`. All commands run from the repo root.
- Installed skills are symlinks into this repo — every commit is a live deploy to both harnesses.
- Tests are bash + grep only; when pinned prose changes, the lint changes in the same commit.
- Conventional commits: `type(scope): description`, imperative, ≤72 chars.
- Stage explicit paths; never `git add -A`. Print `git branch --show-current` and `git status --short` alongside every commit.
- Lane values, verbatim: contained → `gpt-5.6-terra` at `xhigh`; premise-critical → `gpt-5.6-sol` at `xhigh`; escalation `sol`+`max` (single deep chain) or `sol`+`ultra` (coverage-shaped big surface), justification stated to the user BEFORE the run spends the compute; floor is Terra — never `gpt-5.6-luna`.
- `CHARTER.md` is untouched by this plan.

---

### Task 1: Wrapper default effort → xhigh (test-first)

**Files:**
- Modify: `codex/test/test.sh`
- Modify: `codex/run-codex.sh`

**Interfaces:**
- Produces: `run-codex.sh` fallback defaults `effort="xhigh"`, `model="gpt-5.6-sol"` (model unchanged) that Task 2's skill prose describes as "fallback, not the router".

- [ ] **Step 1: Add the failing default-effort test**

In `codex/test/test.sh`, after the `has "model pinned to sol" …` line and before the `# --- guard: non-git repo ---` block, insert:

```bash
# --- wrapper default effort (no --effort flag) ---
: > "$FAKE_CODEX_LOG"
OUTD="$(mktemp -d)"
"$WRAP" run --repo "$REPO" --prompt-file "$PROMPT" --out-dir "$OUTD" >/dev/null 2>"$OUTD/err"
rc=$?
[ "$rc" = 0 ] && ok "default-effort run exits 0" || no "default-effort run exits 0 (rc=$rc, $(cat "$OUTD/err"))"
has "default effort is xhigh" "$(cat "$FAKE_CODEX_LOG")" "model_reasoning_effort=xhigh"
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `codex/test/test.sh | grep -E 'FAIL|passed'`
Expected: `default effort is xhigh` FAILs (the wrapper currently defaults to `high`); everything else passes.

- [ ] **Step 3: Change the wrapper default and usage text**

In `codex/run-codex.sh`, replace:

```bash
effort: high (default, smaller/contained runs) | ultra (complex/architectural runs) | medium | low
model:  default gpt-5.6-sol (needs codex-cli >= 0.144)
```

with:

```bash
effort: xhigh (default) | low | medium | high | max | ultra — max/ultra need a stated justification
model:  default gpt-5.6-sol (needs codex-cli >= 0.144); the skill passes the lane's model explicitly
```

and replace:

```bash
repo="" prompt_file="" out_dir="" effort="high" model="gpt-5.6-sol" session_id=""
```

with:

```bash
repo="" prompt_file="" out_dir="" effort="xhigh" model="gpt-5.6-sol" session_id=""
```

- [ ] **Step 4: Run the test suite to verify it passes**

Run: `codex/test/test.sh | tail -1`
Expected: `… 0 failed` (the existing explicit `--effort high` and `--effort ultra` cases still pass — they override the default).

- [ ] **Step 5: Commit**

```bash
git branch --show-current && git status --short
git add codex/run-codex.sh codex/test/test.sh
git commit -m "feat(codex): default wrapper effort to xhigh"
```

---

### Task 2: Lanes in codex/SKILL.md (+ lint pins)

**Files:**
- Modify: `codex/SKILL.md`
- Modify: `test/lint-skills.sh`

**Interfaces:**
- Consumes: wrapper defaults from Task 1.
- Produces: lane-selection prose with the exact strings the new lint checks pin (`gpt-5.6-terra`, `never \`gpt-5.6-luna\``, `BEFORE the run spends`, `--model "$MODEL" --effort "$EFFORT"`).

- [ ] **Step 1: Add the failing lint checks**

In `test/lint-skills.sh`, after the trace-scenario block and before the final `printf`, insert:

```bash
# --- codex (reviewer lanes) ---
CX="$HERE/../codex/SKILL.md"
CXSH="$HERE/../codex/run-codex.sh"
grep -q '^name: codex$' "$CX" 2>/dev/null && ok "codex: name matches directory" || no "codex: name matches directory"
has   "codex: contained lane on terra"     "gpt-5.6-terra" "$CX"
has   "codex: premise lane on sol"         "gpt-5.6-sol"   "$CX"
has   "codex: luna floor"                  'never `gpt-5.6-luna`' "$CX"
has   "codex: justification before spend"  "BEFORE the run spends" "$CX"
has   "codex: explicit flags on run"       '--model "$MODEL" --effort "$EFFORT"' "$CX"
grep -qE 'gpt-5\.6-terra. at .xhigh' "$CX" \
  && ok "codex: terra lane pinned to xhigh" || no "codex: terra lane pinned to xhigh"
has   "codex wrapper: usage names xhigh default" "xhigh (default)" "$CXSH"
```

Run: `test/lint-skills.sh | grep -E 'FAIL|passed'` — expected: five content checks against `$CX` FAIL (terra lane, luna floor, justification, explicit flags, terra-at-xhigh); the sol-lane check already passes because `gpt-5.6-sol` appears in the pre-edit prose, as do `codex: name matches directory` and the wrapper usage check. Everything else passes.

- [ ] **Step 2: Rewrite step 1 of the skill (lane selection)**

In `codex/SKILL.md`, replace:

```markdown
1. **Goal.** If a goal was passed with the invocation (the hook path, or `/codex <goal>`),
   use it. Otherwise ask the user, in one or two sentences, what the goal of this run is.
   Parse an optional `--effort <ultra|high|medium|low>`. If none was passed, pick it from
   the scope of the run: `high` for smaller, contained work (a single feature, a focused
   spec, a data claim); `ultra` for complex requests — architectural decisions, multi-file
   or cross-cutting changes, or anything where a wrong premise is expensive. An optional
   `--model <slug>` overrides the reviewer model (default `gpt-5.6-sol`).
```

with:

```markdown
1. **Goal and lane.** If a goal was passed with the invocation (the hook path, or
   `/codex <goal>`), use it. Otherwise ask the user, in one or two sentences, what the goal
   of this run is.

   Parse optional `--effort <low|medium|high|xhigh|max|ultra>` and `--model <slug>` overrides,
   then pick the lane — consequence outranks artifact size:

   1. An explicit `--model` / `--effort` from the caller wins.
   2. The automatic spec→plan hook path is premise-critical by definition.
   3. Stakes: if a wrong premise is expensive (architecture, a cross-cutting change, a data
      claim underpinning a big decision) → premise-critical, even when the artifact is small.
   4. Otherwise contained.

   *Contained* (a focused spec, a single feature, a data claim) → `gpt-5.6-terra` at `xhigh`.
   *Premise-critical* → `gpt-5.6-sol` at `xhigh`. Escalation goes depth before orchestration:
   `sol` + `max` for a single deep chain; `sol` + `ultra` only for coverage-shaped review of a
   big surface — either needs a one-line justification stated to the user BEFORE the run spends
   the compute. The floor is Terra — never `gpt-5.6-luna`: independent judgment is the product.
```

- [ ] **Step 3: Pass both flags explicitly on run and resume**

In `codex/SKILL.md` step 4, replace (the blocks below sit between ````markdown markers because they contain inner ``` fences — everything between the four-backtick markers is skill-file content):

````markdown
   ```
   ~/.claude/skills/codex/run-codex.sh run \
     --repo "$repo" --prompt-file "$PROMPT" --out-dir "$OUT" --effort "$EFFORT"
   ```
   On success it writes `$OUT/last.txt` (final prose), `$OUT/session_id.txt` (the thread
   id), and `$OUT/events.jsonl`. The wrapper pins the model to `gpt-5.6-sol`; pass
   `--model` only if the user asked for a different one.
````

with:

````markdown
   ```
   ~/.claude/skills/codex/run-codex.sh run \
     --repo "$repo" --prompt-file "$PROMPT" --out-dir "$OUT" \
     --model "$MODEL" --effort "$EFFORT"
   ```
   On success it writes `$OUT/last.txt` (final prose), `$OUT/session_id.txt` (the thread
   id), and `$OUT/events.jsonl`. Always pass both `--model` and `--effort` explicitly — here
   and on `resume`; the wrapper defaults (`gpt-5.6-sol`, `xhigh`) are a fallback, not the
   router.
````

In step 6 (rebuttal), replace:

```markdown
   ~/.claude/skills/codex/run-codex.sh resume \
     --session-id "$(cat "$OUT/session_id.txt")" \
     --repo "$repo" --prompt-file "$REPLY" --out-dir "$OUT2" --effort "$EFFORT"
```

with:

```markdown
   ~/.claude/skills/codex/run-codex.sh resume \
     --session-id "$(cat "$OUT/session_id.txt")" \
     --repo "$repo" --prompt-file "$REPLY" --out-dir "$OUT2" \
     --model "$MODEL" --effort "$EFFORT"
```

- [ ] **Step 4: Run lint to verify it passes**

Run: `test/lint-skills.sh | tail -1`
Expected: `0 failed`.

- [ ] **Step 5: Commit**

```bash
git branch --show-current && git status --short
git add codex/SKILL.md test/lint-skills.sh
git commit -m "feat(codex): route reviewer runs by lane instead of pinning sol"
```

---

### Task 3: README rewrite + full verification

**Files:**
- Modify: `codex/README.md`

**Interfaces:**
- Consumes: lanes from Task 2, wrapper defaults from Task 1. Produces: nothing downstream — documentation + final gate.

- [ ] **Step 1: Rewrite the stale posture paragraph**

In `codex/README.md`, replace:

```markdown
Posture (fixed): `--sandbox workspace-write`, `-c approval_policy=never`, network on,
reasoning `high` (override per run with `/codex … --effort medium|low`), model inherited
(no `-m`). Data access is **per-project** — the skill hardcodes no database; it uses whatever
```

with:

```markdown
Posture (fixed): `--sandbox workspace-write`, `-c approval_policy=never`, network on.
Model and effort are routed per run by lane: contained → `gpt-5.6-terra` at `xhigh`;
premise-critical → `gpt-5.6-sol` at `xhigh`; escalation (`max`/`ultra`, Sol only) needs a
stated justification; the floor is Terra, never Luna. `--model`/`--effort` override per run.
Data access is **per-project** — the skill hardcodes no database; it uses whatever
```

- [ ] **Step 2: Run every suite**

Run: `test/lint-skills.sh | tail -1 && codex/test/test.sh | tail -1 && sprint-orchestrator/test/test-sprint-status.sh | tail -1`
Expected: three `… 0 failed` lines. (If the sprint/handoff plan has landed, also run `sprint-orchestrator/test/test-wave-handoffs.sh | tail -1`.)

- [ ] **Step 3: Manual acceptance scenario (named, not automated — grep cannot test LLM judgment)**

Record the result in the commit message body or the session notes:

1. Invoke `/codex` with a contained goal (e.g. "validate that sprint-status counts suffixed story numbers") and NO flags → the composed `run-codex.sh` call must carry `--model gpt-5.6-terra --effort xhigh`.
2. Invoke the spec→plan hook path (or `/codex` on an architecture question) → the composed call must carry `--model gpt-5.6-sol --effort xhigh`.
3. Ask for an escalated run → the skill states a one-line justification BEFORE executing, and the call carries `sol` + `max` or `sol` + `ultra`.

- [ ] **Step 4: Commit**

```bash
git branch --show-current && git status --short
git add codex/README.md
git commit -m "docs(codex): document lane routing and terra floor"
```
