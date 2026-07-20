# claude-skills

A personal collection of **global** agent skills — version-controlled here, and installed by
symlinking each skill into an agent's skills directory so it's callable as `/<skill-name>`
(Claude), `$<skill-name>` (Codex), or `/skill:<skill-name>` (Kimi) from any project.

The install mechanism and layout are skill-agnostic; adding one is "drop a directory and
re-run the installer."

| Skill | What it does |
|---|---|
| [`codex`](codex/) | Summons OpenAI Codex as an independent second perspective |
| [`claude-reviewer`](claude-reviewer/) | The mirror of `codex`: Codex summons Claude Code as an independent reviewer |
| [`sprint-orchestrator`](sprint-orchestrator/) | Plans verified story handoffs, supervises the wave, and integrates results; story state derived from git. Planner: Claude (Fable, else Opus) or Kimi |
| [`agent-handoff`](agent-handoff/) | Hands bounded work to another agent — task, visual-validation, and story-execution modes |

`sprint-orchestrator` and `agent-handoff` are companions: one plans, the other hands off.
`claude-reviewer` is Codex-facing; it installs into Claude's list too (the installer links
everything into both), but carries `disable-model-invocation: true` there — from Claude it
would be circular.

## Layout

```
claude-skills/
├── install.sh            # symlinks every skill into $CLAUDE_SKILLS_DIR (default ~/.claude/skills/)
├── test/                 # repo-level invariant checks (lint-skills.sh)
├── <skill-name>/         # one directory per skill (each is installable)
│   ├── SKILL.md          # required: frontmatter (name, description) + instructions
│   ├── README.md         # optional: prerequisites / machine-specific setup
│   ├── agents/           # optional: openai.yaml, Codex's per-skill interface + policy
│   └── test/             # optional: the skill's own tests
└── docs/                 # specs, plans, and review records (not installed as skills)
```

A directory is treated as an installable skill **iff** it contains a `SKILL.md`. Anything
else (like `docs/` and `test/`) is ignored by the installer.

## Install (including on another machine)

The fastest path: clone, then point your agent at the repo.

```bash
git clone https://github.com/rkuprin/claude-skills.git ~/claude-skills
```

Then tell your agent — Claude Code, Codex, or another harness:

> Read ~/claude-skills/INSTALL.md and follow it.

[`INSTALL.md`](INSTALL.md) is the agent-facing guide: it links every skill into each harness
present, runs the machine-specific setup (including the sprint mailbox Stop hook on Codex
machines), verifies with the test suites, and reports back. A human can follow it too.

Doing it by hand instead:

```bash
cd ~/claude-skills
./install.sh                                    # -> ~/.claude/skills/
CLAUDE_SKILLS_DIR=~/.codex/skills ./install.sh  # -> ~/.codex/skills/  (optional)
CLAUDE_SKILLS_DIR=~/.agents/skills ./install.sh # -> ~/.agents/skills/ (optional, Kimi)
```

`install.sh` symlinks every skill directory into `$CLAUDE_SKILLS_DIR` (default
`~/.claude/skills/<name>`). Each agent auto-discovers skills there on the next session; invoke
one with `/<name>` in Claude or `$<name>` in Codex.

Install into both directories to give Claude and Codex the *same file*, so the two can never
drift. Note that `install.sh` links **every** skill in the repo, with no exclusion mechanism —
so a Claude-oriented skill will also appear in Codex's list, and vice versa.

**Some skills need extra, machine-specific setup** (a CLI tool, an API login). After
running `install.sh`, read each skill's own `README.md` for prerequisites. In particular,
`codex/` needs the OpenAI Codex CLI installed and authenticated — see [`codex/README.md`](codex/README.md) —
and `sprint-orchestrator/` needs its per-harness mailbox Stop hooks wired once per machine:
`sprint-orchestrator/install-codex-hook.sh` (Codex) and
`sprint-orchestrator/install-claude-hook.sh` (Claude) — details in
[`sprint-orchestrator/README.md`](sprint-orchestrator/README.md), "Reactive waits on Codex" /
"Reactive waits on Claude". Kimi needs no hook — its waits are cron sweeps the session
schedules itself ("Reactive waits on Kimi").

> **If you are an agent setting this up on a new machine:** follow
> [`INSTALL.md`](INSTALL.md) — it is written for you, verify steps included. Change nothing
> beyond what its steps name; anything extra needs the user's explicit go first.

## Adding a new skill

1. `mkdir ~/claude-skills/<new-skill>`
2. Add `<new-skill>/SKILL.md` with YAML frontmatter:
   ```yaml
   ---
   name: <new-skill>
   description: <when Claude should reach for this skill>
   ---
   ```
   followed by the skill's instructions.
3. (Optional) Add `<new-skill>/README.md` for any prerequisites or setup.
4. Re-run `./install.sh`.

## Updating

```bash
cd ~/claude-skills && git pull && ./install.sh
```

Symlinks follow the repo, so a `git pull` updates installed skills in place; re-running
`install.sh` only matters when you've **added** a skill.
