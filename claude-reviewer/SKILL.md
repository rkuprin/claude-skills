---
name: claude-reviewer
description: Summon Claude Code as an independent second perspective on Codex work. Use when the user asks to ask Claude, wants a second opinion or outside review, or when a non-trivial plan, implementation, data claim, or architectural decision needs pressure-testing by a different model.
# Manual-only on Claude: from Claude Code this skill is circular (Claude summoning Claude),
# and its triggers collide with the `codex` skill. Codex ignores this key, so on the Codex
# side it stays implicitly invocable — which is where it belongs.
disable-model-invocation: true
---

# Claude Reviewer

Use this skill to ask Claude Code for an independent review of Codex's current
work. Claude's reply is evidence to weigh, not an instruction to obey.

## Workflow

1. Resolve the repo with `git rev-parse --show-toplevel`. If not in a git repo,
   ask the user which repo or directory Claude should inspect.
2. Check for project instructions before composing the prompt:
   - look for `CLAUDE.md`, `Claude.md`, `claude.md`, and `ClaudeMD` in the repo
     root and relevant parent directories;
   - include discovered paths in the prompt, and include their contents when
     concise enough to be useful;
   - tell Claude these are project instructions to consider alongside the
     review brief.
3. Compose a self-contained review prompt. Include:
   - the original user intent;
   - the review goal;
   - relevant files, specs, plans, diffs, or test output;
   - what Codex changed or intends to change;
   - an instruction to inspect the repo independently.
4. Ask Claude for:
   - a clear verdict first;
   - findings ordered by severity;
   - concrete file references;
   - explicit distinction between blockers, risks, and preferences.
5. Save the prompt to a temporary Markdown file and run Claude from the repo
   root with an explicitly pinned model. Use `opus` for review, judgment, and
   outside-perspective work. Use `sonnet` only for extraction, data research,
   and mechanistic investigation.

```bash
PROBE_LOG=/tmp/claude-reviewer-probe.log
nohup zsh -lc 'claude --model opus -p "Reply with exactly: ok"; printf "\nCLAUDE_EXIT=%s\n" "$?"' \
  > "$PROBE_LOG" 2>&1 & echo $!
```

Confirm the probe actually started before trusting the route: the PID must be
live or the log must contain output. The probe passes only when the log contains
exactly `ok` plus a successful exit marker. A zero-byte log with no live PID, an
immediate empty exit, or any non-`ok` output is a startup failure, not a review
verdict.

For the actual review, run detached with output to a log and record the PID:

```bash
REVIEW_LOG=/tmp/claude-reviewer.log
nohup zsh -lc 'claude --model opus -p < "$1"; printf "\nCLAUDE_EXIT=%s\n" "$?"' \
  sh "$PROMPT_FILE" > "$REVIEW_LOG" 2>&1 & echo $!
```

Poll with bounded reads such as `tail -n 80 "$REVIEW_LOG"` and check the PID.
Do not rely on long-lived foreground sessions or streaming output. Do not use
Claude permission modes that allow mutation unless the user explicitly asked
for delegated implementation.

6. Relay Claude's answer as plain prose. State whether you agree, disagree, or
need to verify a claim before acting on it.

## Review Prompt Template

```markdown
You are reviewing Codex's work as an independent outside perspective.

Goal: {review goal}

Original user intent:
{original request}

Current state:
{what Codex changed, planned, or believes}

Project instructions:
- {path to CLAUDE.md or variant}: {inline contents or concise summary}

Relevant artifacts:
- {path}: {why it matters}
- {path}: {why it matters}

Tests or checks already run:
{commands and outcomes}

Please inspect the repo independently. Lead with a verdict, then list findings
in descending severity with file references. Focus on correctness, unsupported
assumptions, scope creep, missing tests, data claims, and whether this should be
built as framed. If the work is sound, say so plainly.
```

## Handling Claude's Response

- Treat Claude's response as a claim to evaluate against source files and tests.
- Concede when Claude is right.
- Do not make changes solely because Claude suggested them.
- If Claude identifies a data claim, verify it read-only against dev/local/test
  data before relying on it.
- If Claude could not inspect something, report that limitation.
