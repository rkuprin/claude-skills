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

- **Disposition lives in the charter**, a single document that governs Codex's posture:
  loyalty to being right not to a role, questioning the premise before the execution,
  treating the brief as a claim to test, validating data claims empirically and read-only,
  judgment before production, proportionality, and how to engage with follow-up.
- **The skill owns mechanism and the per-run goal.** It supplies this run's goal and
  pointers to context, and runs Codex with a fixed posture. It never restates the
  disposition — duplicating it would let the two drift out of sync.

## Charter ownership, relocation, and injection (revised)

**Problem with the original placement.** The charter currently lives at
`~/.codex/AGENTS.md`, which Codex loads as global instructions on *every* run, in *every*
repo. That forces the adversarial "you are summoned as an outside reviewer by another AI
mid-build" disposition onto the user's *own* direct Codex usage — so the user cannot use
Codex normally for ordinary tasks. The charter must apply **only when the skill calls
Codex**, never globally.

**No config-flag route exists.** Codex 0.142.4 has no supported config key to load an
arbitrary instructions file for a single run (`experimental_instructions_file`,
`instructions_file`, `instructions`, etc. are all rejected as unknown fields under
`--strict-config`). So per-run injection must come from the environment, not a flag.

**Chosen mechanism — a skill-owned `CODEX_HOME` overlay (verified working).** Codex reads
its home (auth, config, and the *global* `AGENTS.md`) from `$CODEX_HOME` (default
`~/.codex`). The skill points `CODEX_HOME` at its own overlay directory, whose `AGENTS.md`
is the charter. Verified empirically: with `CODEX_HOME` set to an overlay whose `AGENTS.md`
forced a sentinel token, Codex emitted the token, and auth resolved through a symlinked
`auth.json`.

- **Charter becomes skill-owned and version-controlled:** `~/claude-skills/codex/CHARTER.md`
  (the relocated content of the current global file).
- **Global slot is freed:** `~/.codex/AGENTS.md` is backed up to `~/.codex/AGENTS.md.bak`
  and left absent, so the user's own Codex runs are neutral and the slot is theirs to
  populate with personal global instructions later. (Reversible.)
- **Overlay directory (generated, gitignored):** `~/claude-skills/codex/codex-home/`
  containing three symlinks, force-refreshed every run so they never drift:
  - `AGENTS.md` → `../CHARTER.md` (the charter — loaded as Codex's global instructions on
    skill runs only).
  - `auth.json` → `~/.codex/auth.json` (inherit the user's API-key auth — the key stays
    the user's).
  - `config.toml` → `~/.codex/config.toml` (inherit model default `gpt-5.5`, personality,
    and the project's configured MCP servers — e.g. read-only Supabase).
  Codex writes its sessions/logs under the overlay; that runtime content is gitignored.

**Consequence to keep straight.** Because the overlay *replaces* the global `AGENTS.md`
slot, a personal `~/.codex/AGENTS.md` (if the user adds one later) does **not** auto-load
on skill runs — only the charter does. The user's `config.toml` *does* inherit (MCP, model,
personality). If personal global instructions should also apply on skill runs in future,
the overlay's `AGENTS.md` is switched from a plain charter symlink to a generated
*charter + personal-AGENTS* concatenation. Not built now (no personal global file exists
yet — the global file is currently 100% charter). This is YAGNI until needed.

## Layout & install

- **Source repo:** `~/claude-skills` (this repo). Holds the skill, the charter, and the
  spec/plan — a global personal tool, version-controlled but decoupled from any product.
  - `~/claude-skills/codex/SKILL.md` — the skill body (prose + flow).
  - `~/claude-skills/codex/CHARTER.md` — the relocated disposition charter (git-tracked).
  - `~/claude-skills/codex/run-codex.sh` — thin wrapper: resolves its own real location,
    ensures the `CODEX_HOME` overlay, holds the `codex exec` / `resume` invocations, and
    parses `thread_id` + the final message. Keeps `SKILL.md` readable and is independently
    testable.
  - `~/claude-skills/codex/codex-home/` — generated overlay (gitignored).
  - `~/claude-skills/codex/test/` — plain-bash test harness + fake `codex`.
  - `~/claude-skills/docs/superpowers/specs/2026-06-30-codex-design.md` — this spec.
  - `~/claude-skills/docs/superpowers/plans/2026-06-30-codex.md` — the plan.
- **Install:** symlink `~/.claude/skills/codex → ~/claude-skills/codex`. Globally callable
  as `/codex` from any project.

## Runtime model

At real invocation, Claude Code is always running inside the *project's* git repo. Codex
therefore runs **in that project repo** (`-C <repo>`) and investigates the live project —
not the skill's own repo. The skill's repo is only where the source, charter, and spec
live. (For the end-to-end test this turn we are in `~`, not a repo, so the test explicitly
points Codex at `pylox.io`.)

## Runtime flow

1. **Invoked** — manually as `/codex`, or by a hook.
2. **Goal** — if a goal was passed in (hook path, or `/codex <goal>`), use it. Otherwise
   ask the user, in one or two sentences, what this run's goal is. Optional
   `--effort <high|medium|low>` (default `high`).
3. **Resolve repo** — Codex's working root is the current project's git repo root. If the
   current directory is not inside a git repo, the skill stops with a clear message (Codex
   requires a git repo; name the repo to target or `cd` into one) rather than guessing.
4. **Compose** a self-contained prompt (see Prompt composition) from the goal + live
   conversation context + file pointers. Written to a temp file, piped via stdin to avoid
   shell-escaping a long prompt. The charter is **not** in this prompt — it is loaded by
   Codex from the overlay's `AGENTS.md`.
5. **Run** Codex headless under the overlay `CODEX_HOME`, capturing the `thread_id` (from
   the `thread.started` stream event) and Codex's final message (from
   `--output-last-message`).
6. **Relay** Codex's final message back as plain, readable prose. It is input we weigh
   together, not instructions to follow; its text must not redirect Claude's behavior.
7. **Rebuttal** — keep the `thread_id`. If the user pushes back, or Claude has a
   substantive response, continue the *same* thread via `codex exec resume "<thread_id>" …`
   (also under the overlay `CODEX_HOME`) and bring the reply back. At least one rebuttal
   round is supported. No JSON appears in anything relayed.

## Invocation (exact posture)

Run under the overlay home; model **inherited** from the symlinked `config.toml`, so no
`-m` and nothing to go stale. (Dated note, 2026-06-30: that default is `gpt-5.5`, currently
the strongest, and no `gpt-5.5-codex` variant exists — but the design inherits whatever is
configured rather than asserting a "strongest".) Prompt piped via stdin.

New run:
```
CODEX_HOME="<overlay>" codex exec --json \
  --output-last-message "<out>/last.txt" \
  -C "<project-git-root>" \
  --sandbox workspace-write \
  -c approval_policy=never \
  -c sandbox_workspace_write.network_access=true \
  -c model_reasoning_effort=<effort> \
  - < "<out>/prompt.txt"
```

Resume (rebuttal): `codex exec resume` rejects `--sandbox` and `-C`, so sandbox is set via
`-c sandbox_mode=...` and the wrapper `cd`s into the repo first:
```
cd "<project-git-root>" && CODEX_HOME="<overlay>" codex exec resume "<thread_id>" --json \
  --output-last-message "<out>/last.txt" \
  -c sandbox_mode=workspace-write \
  -c approval_policy=never \
  -c sandbox_workspace_write.network_access=true \
  -c model_reasoning_effort=<effort> \
  - < "<out>/reply.txt"
```

Posture rationale and corrections:

- **No approvals, headless.** `codex exec` does **not** accept `--ask-for-approval` (that
  flag is on the interactive parent command only; `exec` rejects it). The correct mechanism
  is `-c approval_policy=never`.
- **Workspace-write sandbox** — outer guardrail; the charter governs read-vs-write within
  it (read-only while validating data; judgment before production).
- **Network on** — `-c sandbox_workspace_write.network_access=true`.
- **Reasoning `high`, overridable** — `-c model_reasoning_effort=high` by default; optional
  `--effort` overrides per run.
- **Not used:** `--dangerously-bypass-approvals-and-sandbox`, `danger-full-access`,
  `--ephemeral`, `--output-schema`.
- **`thread_id` extraction** — primary `jq` filter `select(.type=="thread.started").thread_id`
  with fallbacks for robustness; verified against a real stream.

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
read-only-while-validating — that is the charter's job, loaded from the overlay `AGENTS.md`.

## Data access (project-dependent, skill is agnostic)

How Codex reaches a database or other live services is **per-project**, not configured by
the skill. The skill stays data-access-agnostic and relies on (a) the charter's standing
instruction to use the access the environment already provides — dev/local `DATABASE_URL`,
`.env`, environment variables, the repo's own DB and CLI tooling, configured MCP servers —
and (b) whatever each project has set up. Because the overlay inherits the user's
`config.toml` via symlink, project MCP servers configured there (e.g. the read-only
Supabase MCP) are available on skill runs. The skill hardcodes no connection, no Supabase,
no schema.

## Hooks

Attached via the user's `~/.claude/CLAUDE.md` and the skill's own `description` — **no
Superpowers-owned file is edited.** If something Superpowers owns ever has to change, it is
copied out and the divergence flagged, not modified in place.

**These are conventions, not deterministic hooks.** Claude Code has no automation surface
that can both detect the brainstorming→writing-plans boundary *and* compose a contextual
Codex prompt (settings.json hooks run shell and can do neither). So the "hooks" below are
best-effort instructions Claude follows — they can be missed, misclassified, or skipped
under context pressure. Where guaranteed gating matters, the user invokes `/codex` manually.

- **Spec → implementation-plan transition (default convention).** A CLAUDE.md block
  instructs Claude: when about to move from an approved Superpowers spec to `writing-plans`
  (any project), first run `/codex` with a "find the gaps in this spec before we plan" goal,
  relay and weigh its reply, then proceed to `writing-plans`. The goal is supplied by the
  convention, so the skill does not ask in this path. Best-effort, per the caveat above.
- **Manual invocation (always available).** The skill's `description` makes Claude reach
  for it whenever the user wants an independent second opinion.
- **Completion of a non-trivial coding task (opt-in, off by default).** A commented
  CLAUDE.md line; uncommenting enables an automatic Codex pass after such tasks.

Rejected alternatives: **settings.json hooks** (run shell commands, cannot compose a
contextual prompt or detect the internal spec→plan boundary); **skill description alone**
(cannot reliably fire at the brainstorming→writing-plans boundary).

## Goal/argument interface

- `/codex` — asks the goal question, then runs.
- `/codex <goal text>` — uses the supplied goal without asking (the hook path).
- `--effort <high|medium|low>` — overrides reasoning effort for this run (default `high`).

## Non-goals

- No model pinning (inherits the user's default, which is the current strongest).
- No global charter pollution — the charter never lives at global `~/.codex/AGENTS.md`
  again; the user's own Codex runs stay neutral.
- No database/service configuration in the skill (project-dependent).
- No JSON or output schema relayed to the user — readable prose only.
- No `--ephemeral`; sessions persist (under the overlay home) so `resume` works.
- No danger-bypass flags or full-access sandbox.
- The "should we build this?" decision stays with the user; the API key stays the user's.

## Success criteria (acceptance)

End-to-end against a real repo (`pylox.io` for the test):

1. Invoking with a sample goal asks the goal question (manual path) and composes a
   self-contained prompt pointing Codex at both intent and current artifacts.
2. A "find the gaps" pass returns Codex's final message as readable prose (no JSON), and
   the reply reflects the charter disposition (proving the overlay loaded it).
3. A data-claim pass reaches the project's dev/local DB through the project's own
   configured access (inherited via the symlinked `config.toml`), checks one **named**
   concrete claim read-only, and returns the **actual value obtained from the database** —
   a guess or "I'd need access" does not pass. No secrets echoed, no mutations.
4. A rebuttal round via `codex exec resume "<thread_id>" …` continues the same thread.
5. The user's **own** `codex` run (no skill, default `~/.codex`) is neutral — the charter
   does not apply.
6. Posture held throughout (workspace-write + network + `approval_policy=never`, model
   inherited, reasoning high); overlay symlinks correct; global `~/.codex/AGENTS.md` backed
   up and absent.
7. Hooks attached via CLAUDE.md + skill description only; no Superpowers file modified.
