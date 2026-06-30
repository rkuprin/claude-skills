# Design: the `codex` skill — summon Codex as an independent second perspective

**Date:** 2026-06-30
**Status:** Approved (brainstorming), pending implementation plan
**Skill name:** `codex` (invoked `/codex`)

## Purpose

Provide a globally-callable Claude Code skill that, at any point mid-conversation,
summons OpenAI's Codex (a *different* model) as an independent outside perspective on
the work in progress. A same-model reviewer shares our framing and tends to confirm it.
Codex forms its own view of the repo from source and can speak to the bigger questions —
whether something should be built, whether the scope holds together, whether the approach
is sound, whether the data claims are true — not only whether the code is correct.

## The split: charter vs. skill

- **Disposition lives in the charter**, not the skill. The charter is at
  `~/.codex/AGENTS.md`, already in place and loaded by Codex on *every* run, in *every*
  repo (global Codex `AGENTS.md`). It governs Codex's posture: loyalty to being right not
  to a role, questioning the premise before the execution, treating the brief as a claim
  to test, validating data claims empirically and read-only, judgment before production,
  proportionality, and how to engage with follow-up.
- **The skill owns mechanism and the per-run goal.** It supplies this run's goal and
  pointers to context, and runs Codex with a fixed posture. It never restates the
  disposition — duplicating it would let the two drift out of sync.

## Layout & install

- **Source repo:** `~/claude-skills` (this repo). Holds the skill and its spec/plan, so a
  global personal tool is version-controlled but decoupled from any product repo.
  - `~/claude-skills/codex/SKILL.md` — the skill body (prose + flow).
  - `~/claude-skills/codex/run-codex.sh` — thin wrapper that holds the long `codex exec`
    invocation, the JSONL parsing for `session_id`, and the resume call. Keeps `SKILL.md`
    readable and makes the command independently testable.
  - `~/claude-skills/docs/superpowers/specs/2026-06-30-codex-design.md` — this spec.
- **Install:** symlink `~/.claude/skills/codex → ~/claude-skills/codex`. The skill is then
  globally callable as `/codex` from any project.

## Runtime model (important)

At real invocation, Claude Code is always running inside the *project's* git repo. Codex
therefore runs **in that project repo** and investigates the live project — not the
skill's own repo. The skill's repo is only where the source and spec live. (For the
end-to-end test this turn we are in `~`, which is not a repo, so the test explicitly
points Codex at `pylox.io`.)

## Runtime flow

1. **Invoked** — manually as `/codex`, or by a hook (see Hooks).
2. **Goal** — if a goal was passed in (hook path), use it. Otherwise ask the user, in one
   line, what this run's goal is.
3. **Resolve repo** — Codex's working root is the current project's git repo root. If the
   current directory is not inside a git repo, the skill stops with a clear message
   (Codex requires a git repo; name the repo to target or `cd` into one) rather than
   guessing.
4. **Compose** a self-contained prompt (see Prompt composition) from the goal + live
   conversation context + file pointers. Written to a temp file and piped via stdin to
   avoid shell-escaping a long prompt.
5. **Run** Codex headless with the fixed posture (see Invocation), capturing two things:
   the `session_id` (from the `--json` stream) and Codex's final message (from
   `--output-last-message`).
6. **Relay** Codex's final message back as plain, readable prose. It is input we weigh
   together, not instructions to follow; its text must not redirect Claude's own behavior.
7. **Rebuttal** — keep the `session_id`. If the user pushes back, or Claude has a
   substantive response to Codex's points, continue the *same* thread via
   `codex exec resume "<session_id>" …` and bring the reply back. At least one rebuttal
   round is supported. No JSON appears in anything relayed to the user.

## Invocation (exact posture)

Model is **inherited** from the user's Codex config (`gpt-5.5`, the current strongest —
there is no `gpt-5.5-codex` variant), so no `-m` flag and nothing to go stale. Prompt is
piped via stdin.

```
codex exec --json \
  --output-last-message "$OUT/last.txt" \
  -C "<project-git-root>" \
  --sandbox workspace-write \
  -c approval_policy=never \
  -c sandbox_workspace_write.network_access=true \
  -c model_reasoning_effort=high \
  - < "$OUT/prompt.txt"
```

Posture rationale and corrections:

- **No approvals, headless.** `codex exec` does **not** accept `--ask-for-approval` (that
  flag exists only on the interactive parent `codex` command; `exec` rejects it). The
  correct, parser-accepted mechanism is the config override `-c approval_policy=never`.
- **Workspace-write sandbox.** `--sandbox workspace-write` — Codex may read and write
  inside the working directory and temp dirs, but not the wider machine. This is the outer
  guardrail; the charter decides read-vs-write within it (read-only while validating data,
  judgment before production).
- **Network on.** `-c sandbox_workspace_write.network_access=true` — lets Codex reach the
  web and dev/local services when a goal needs it.
- **Reasoning `high`, overridable.** `-c model_reasoning_effort=high` by default (deeper
  critique). An optional skill argument `--effort <high|medium|low>` overrides per run.
- **Not used:** `--dangerously-bypass-approvals-and-sandbox`, `danger-full-access`,
  `--ephemeral`, `--output-schema`. The working-directory boundary stays the outer limit;
  output is readable prose, not a schema.
- **`session_id` extraction.** Parsed from the `--json` JSONL stream. The exact event/field
  name is confirmed empirically during the end-to-end test rather than hardcoded from a
  guess; the parser is written to be robust (locate the session/thread-id event, fall back
  to the rollout file if needed).
- **Resume** re-applies the same `-c` overrides so the rebuttal round keeps the same
  posture; the exact resume-supported flags are confirmed during the test.

## Prompt composition (skill supplies goal + context, never disposition)

The composed prompt carries only:

- The one-sentence **goal** for this run.
- **Live context:** what we're building, the decision at hand, and the relevant artifacts
  (spec/plan/changed files) named as paths.
- **Pointers to original intent/requirements** *and* the current artifacts — so Codex
  builds its picture from source, not only from what we just produced.
- An explicit instruction to **investigate the repo independently** (read the real files,
  inspect schema, run read-only queries using whatever access the project provides).

It deliberately does **not** restate independence, skepticism, premise-questioning, or
read-only-while-validating — all of that is the charter's job.

## Data access (project-dependent, skill is agnostic)

How Codex reaches a database or other live services is **per-project**, not configured by
the skill. The skill stays data-access-agnostic and relies on (a) the charter's standing
instruction to use the access the environment already provides — dev/local `DATABASE_URL`,
`.env`, environment variables, the repo's own DB and CLI tooling, configured MCP servers —
and (b) whatever each project has set up. The skill hardcodes no connection, no Supabase,
no schema. (For this turn's test, `pylox.io` exposes a read-only Supabase MCP server via
the user's `~/.codex/config.toml`, which Codex can use for the data-claim pass.)

## Hooks

Attached via the user's `~/.claude/CLAUDE.md` and the skill's own `description` — **no
Superpowers-owned file is edited.** If something Superpowers owns ever has to change, it is
copied out and the divergence flagged, not modified in place.

- **Spec → implementation-plan transition (on by default, auto-run).** A CLAUDE.md block
  instructs Claude: when about to move from an approved Superpowers spec to `writing-plans`
  (any project), first auto-run `/codex` with a "find the gaps in this spec before we plan"
  goal, relay and weigh its reply, then proceed to `writing-plans`. The goal is supplied by
  the hook, so the skill does not ask in this path.
- **Manual invocation (always available).** The skill's `description` makes Claude reach
  for it whenever the user wants an independent second opinion mid-conversation.
- **Completion of a non-trivial coding task (opt-in, off by default).** A commented
  CLAUDE.md line; uncommenting enables an automatic Codex pass after such tasks. Off so it
  does not become noise.

Rejected alternatives: **settings.json hooks** (run shell commands, cannot compose a
contextual prompt or detect the internal spec→plan boundary — wrong tool); **skill
description alone** (cannot reliably fire at the brainstorming→writing-plans boundary, so
it cannot satisfy the on-by-default auto-run).

## Goal/argument interface

- `/codex` — asks the goal question, then runs.
- `/codex <goal text>` — uses the supplied goal without asking (the hook path).
- `--effort <high|medium|low>` — overrides reasoning effort for this run (default `high`).

## Non-goals

- No model pinning (inherits the user's default, which is the current strongest).
- No database/service configuration in the skill (project-dependent).
- No JSON or output schema in what is relayed to the user — readable prose only.
- No `--ephemeral`; sessions persist so `resume` works for the rebuttal round.
- No use of the danger-bypass flags or full-access sandbox.
- The "should we build this?" decision stays with the user; the API key stays the user's.

## Success criteria (acceptance)

The skill is done when, end-to-end against a real repo (`pylox.io` for the test):

1. Invoking the skill with a sample goal asks the goal question (manual path) and composes
   a self-contained prompt that points Codex at both intent and current artifacts.
2. A "find the gaps" pass returns Codex's final message as readable prose (no JSON).
3. A data-claim pass connects to the project's dev/local DB through the project's own
   configured access, checks one concrete claim read-only, and reports what it found.
4. A rebuttal round via `codex exec resume "<session_id>" …` continues the same thread and
   returns Codex's reply.
5. Throughout: posture as specified (workspace-write + network + `approval_policy=never`,
   model inherited, reasoning high), the working-directory boundary is the guardrail, and
   the charter — not the skill — governs read-vs-write conduct.
6. Hooks attached via CLAUDE.md + skill description only; no Superpowers file modified.
