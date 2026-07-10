# claude-skills — agent instructions

Personal global skills, version-controlled here and symlinked into `~/.claude/skills/` and
`~/.codex/skills/`. See `README.md` for layout and install.

## Edits are live

Installed skills are symlinks into this repo. Any edit to a `SKILL.md`, `EXECUTION.md`, or
`agents/openai.yaml` takes effect in **both** harnesses on their next session — there is no
staging copy. Treat every edit as a deploy.

## Prose is the product — lint it

`test/lint-skills.sh` pins the invariants the skill prose must hold. Run it after any edit
to a skill file. When you change pinned prose (a rule, a trailer, a mode name, a guard),
update the lint in the same commit — a passing lint that no longer checks the real string
is worse than no lint.

Per-skill tests sit next to what they test; run the one beside anything you touched:

```bash
test/lint-skills.sh
codex/test/test.sh
sprint-orchestrator/test/test-sprint-status.sh
```

All tests are bash + grep only — no YAML parser, no other runtime. Keep new checks in that
dialect.

## Frontmatter rules

- `name:` must equal the skill's directory name.
- A `description:` containing a colon (e.g. `Triggers:`) must be a **double-quoted scalar**.
  An unquoted one parses as nested YAML and silently breaks auto-invocation — this killed a
  previous skill.
- A skill that must never fire on its own needs **both** guards, because each harness reads
  only its own key: `disable-model-invocation: true` in `SKILL.md` (Claude) and
  `policy.allow_implicit_invocation: false` in `agents/openai.yaml` (Codex).

## Prose rules

- Never write `git checkout main` as an instruction — only inside a negation ("never run…").
  The lint rejects un-negated occurrences in the agent-handoff files.
- Skill instructions are read by an agent with no session context. Spell out paths and
  rules in place; don't reference "the convention above" across files.

## Layout facts

- A skill is any top-level directory containing a `SKILL.md`. `install.sh` links **every**
  such directory into the target skills dir — there is no exclusion mechanism.
- `docs/` holds specs, plans, and review records (superpowers layout); it is not installed.
- `AGENTS.md` is a symlink to this file so Codex reads the same instructions.
