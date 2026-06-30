# claude-skills

A personal collection of **global** Claude Code skills — version-controlled here, and
installed by symlinking each skill into your Claude skills directory so it's callable as
`/<skill-name>` from any project.

This repo is deliberately generic: it can hold any number of skills. Today it has one
(`codex`), but the install mechanism and layout are skill-agnostic, so adding more is just
"drop a directory and re-run the installer."

## Layout

```
claude-skills/
├── install.sh            # symlinks every skill into ~/.claude/skills/
├── <skill-name>/         # one directory per skill (each is installable)
│   ├── SKILL.md          # required: frontmatter (name, description) + instructions
│   └── README.md         # optional: prerequisites / machine-specific setup
└── docs/                 # specs, plans, and review records (not installed as skills)
```

A directory is treated as an installable skill **iff** it contains a `SKILL.md`. Anything
else (like `docs/`) is ignored by the installer.

## Install (including on another machine)

```bash
git clone <this-repo-url> ~/claude-skills      # or copy the folder to ~/claude-skills
cd ~/claude-skills
./install.sh
```

`install.sh` symlinks every skill directory into `~/.claude/skills/<name>` (override the
destination with `CLAUDE_SKILLS_DIR=…`). Claude Code auto-discovers skills there on the next
session; invoke one with `/<name>`.

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
