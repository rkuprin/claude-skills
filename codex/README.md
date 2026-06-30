# codex skill

Summons OpenAI Codex (a *different* model) as an independent second perspective on the
current work — to pressure-test premise, scope, approach, and data claims, not just code
correctness. Invoke with `/codex`. See [`SKILL.md`](SKILL.md) for the per-run flow and
[`../docs/superpowers/specs/2026-06-30-codex-design.md`](../docs/superpowers/specs/2026-06-30-codex-design.md)
for the full design.

## Prerequisites (per machine)

1. **OpenAI Codex CLI installed** — `npm i -g @openai/codex` (the skill calls `codex exec`).
2. **Authenticated** — run `codex login` (or configure an API key) so `~/.codex/auth.json`
   exists. The skill inherits your auth; the API key stays yours.
3. **`jq`** on PATH (used to parse the session id from Codex's JSON stream).
4. Recommended: a `~/.codex/config.toml` (so your model default and any per-project MCP
   servers are inherited on skill runs). Not strictly required.

No project setup is needed beyond being inside a git repo when you invoke `/codex` — Codex
runs with that repo as its working root.

## How the reviewer disposition is injected

Codex's reviewer disposition lives in [`CHARTER.md`](CHARTER.md) (shipped with this repo).
It is **not** placed in your global `~/.codex/AGENTS.md` — that would force reviewer-mode
onto your own everyday `codex` runs. Instead, `run-codex.sh` builds a `CODEX_HOME` overlay
at `codex-home/` (auto-created, git-ignored) on each run:

```
codex-home/AGENTS.md   -> ../CHARTER.md          # charter loaded as Codex's global instructions
codex-home/auth.json   -> ~/.codex/auth.json     # inherit your auth
codex-home/config.toml -> ~/.codex/config.toml   # inherit model default + per-project MCP
```

and runs `CODEX_HOME=codex-home codex exec …`. So the charter applies **only on skill runs**;
your direct `codex` invocations are unaffected.

Posture (fixed): `--sandbox workspace-write`, `-c approval_policy=never`, network on,
reasoning `high` (override per run with `/codex … --effort medium|low`), model inherited
(no `-m`). Data access is **per-project** — the skill hardcodes no database; it uses whatever
access the project provides (env vars, the repo's CLI tooling, a project-scoped MCP server).

## Optional: free the global AGENTS.md slot

If a machine's global `~/.codex/AGENTS.md` already contains this reviewer charter and you want
your own `codex` runs to be neutral, relocate it (back it up, then remove it) so only the
skill injects the charter:

```bash
# only if ~/.codex/AGENTS.md IS the reviewer charter (check first)
cp ~/.codex/AGENTS.md ~/claude-skills/codex/CHARTER.md   # keep the repo copy authoritative
mv ~/.codex/AGENTS.md ~/.codex/AGENTS.md.$(date +%Y%m%d-%H%M%S).bak
```

On a fresh machine you usually have **no** global `~/.codex/AGENTS.md`, so there's nothing to
do — `CHARTER.md` already ships in this repo and the overlay supplies it.
