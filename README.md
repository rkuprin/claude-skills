# claude-skills

A personal collection of **global** agent skills — version-controlled here, and installed by
symlinking each skill into an agent's skills directory so it's callable as `/<skill-name>`
(Claude) or `$<skill-name>` (Codex) from any project.

The install mechanism and layout are skill-agnostic; adding one is "drop a directory and
re-run the installer."

| Skill | What it does |
|---|---|
| [`codex`](codex/) | Summons OpenAI Codex as an independent second perspective |
| [`sprint-orchestrator`](sprint-orchestrator/) | Turns raw sprint inputs into verified story handoff docs; derives story state from git |
| [`agent-handoff`](agent-handoff/) | Hands bounded work to another agent — task, visual-validation, and story-execution modes |

The last two are companions: one plans, the other hands off.

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

```bash
git clone https://github.com/rkuprin/claude-skills.git ~/claude-skills
cd ~/claude-skills
./install.sh                                    # -> ~/.claude/skills/
CLAUDE_SKILLS_DIR=~/.codex/skills ./install.sh  # -> ~/.codex/skills/  (optional)
```

`install.sh` symlinks every skill directory into `$CLAUDE_SKILLS_DIR` (default
`~/.claude/skills/<name>`). Each agent auto-discovers skills there on the next session; invoke
one with `/<name>` in Claude or `$<name>` in Codex.

Install into both directories to give Claude and Codex the *same file*, so the two can never
drift. Note that `install.sh` links **every** skill in the repo, with no exclusion mechanism —
so a Claude-oriented skill will also appear in Codex's list, and vice versa.

**Some skills need extra, machine-specific setup** (a CLI tool, an API login). After
running `install.sh`, read each skill's own `README.md` for prerequisites. In particular,
`codex/` needs the OpenAI Codex CLI installed and authenticated — see [`codex/README.md`](codex/README.md).

> **If you are a Claude instance setting this up on a new machine:** run `./install.sh`,
> then open each skill's `README.md` and satisfy its prerequisites. Do not edit the user's
> global config beyond what a skill's README explicitly calls for; ask first.

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
