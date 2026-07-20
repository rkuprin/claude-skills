# Agent install guide

Written for an agent — Claude Code, Codex, or another harness — executing this repo's setup
on a user's machine. Follow it top to bottom; every step has a verify. A human can follow it
too; nothing here requires agent powers.

**Boundary: change nothing on this machine beyond what these steps name.** Anything extra —
shell profiles, unrelated config, existing skills directories with real files in them — needs
the user's explicit go first.

## 0. Locate the clone and the harnesses

- Repo root: the directory this file sits in (canonical clone: `~/claude-skills`).
- Detect harnesses: `~/.claude` exists → Claude Code is present; `~/.codex` exists → Codex is
  present; `~/.kimi-code` exists → Kimi is present. For another harness that discovers skills
  from a directory, use its skills dir wherever a skills path appears below.

## 1. Link the skills

From the repo root, once per harness present:

```bash
./install.sh                                    # -> ~/.claude/skills/   (Claude Code)
CLAUDE_SKILLS_DIR=~/.codex/skills ./install.sh  # -> ~/.codex/skills/    (Codex)
CLAUDE_SKILLS_DIR=~/.agents/skills ./install.sh # -> ~/.agents/skills/   (Kimi)
```

Install into every harness present so they all run the **same files** and can never drift.
Verify: `ls -l ~/.claude/skills ~/.codex/skills` shows one symlink per skill directory,
each pointing back into this repo.

## 2. Machine-specific setup per skill

- **codex** (summons Codex as a second perspective): needs the OpenAI Codex CLI installed and
  authenticated. Verify: `codex login status`. Details: [`codex/README.md`](codex/README.md).
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
  - Kimi present: nothing to wire — Kimi has no Stop-hook wait; its sessions wait via cron
    sweeps they schedule themselves. Details:
    [`sprint-orchestrator/README.md`](sprint-orchestrator/README.md), "Reactive waits on Kimi".
- **claude-reviewer** (Codex summons Claude as reviewer): needs the Claude Code CLI on PATH;
  nothing else.
- **agent-handoff**: no machine setup.

## 3. Verify the clone is healthy

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

Every suite must end `N passed, 0 failed`.

## 4. Report

Tell the user in one short list: which harnesses were linked, whether each present harness's
mailbox Stop hook is wired (Codex: wired **and trusted**; Claude: wired, plus any
disabled-hooks warning), any missing prerequisites (for example a codex CLI that is not
authenticated), and the test tally. Skills appear in each harness's list on its **next**
session — `/agent-handoff` in Claude Code, `$agent-handoff` in Codex.

---

Installing is what this file covers. Working **on** the repo itself — editing skills, tests,
prose — is covered by [`AGENTS.md`](AGENTS.md) instead.
