# Codex self-review of the codex skill (design dogfood)

**Date:** 2026-06-30 · **Thread:** `019f1954-c511-7272-b493-bb6538716d36` · model `gpt-5.5`, reasoning high

Codex reviewed its own skill design (spec + plan) via the `CODEX_HOME` overlay mechanism the plan prescribes. Findings #2,#3,#4,#5,#6,#7 and the #1 clarification were folded into the spec/plan. Verbatim below.

## Review (initial)

**Verdict:** build the core idea, but do not build this exact plan unchanged. The `CODEX_HOME` overlay is a sound mechanism for scoped Codex reviewer instructions, and the local CLI checks support the main command-shape corrections. The weakest point is that the plan treats best-effort Claude instructions and out-of-repo user config mutation as if they were deterministic, testable infrastructure.

Strongest issues:

1. **The plan is not executable under the stated write permissions.**  
   Task 1 mutates `~/.codex/AGENTS.md`, Task 6 writes `~/.claude/skills/codex`, and Task 7 appends to `~/.claude/CLAUDE.md` ([plan:36](/Users/rkuprin/claude-skills/docs/superpowers/plans/2026-06-30-codex.md:36), [plan:470](/Users/rkuprin/claude-skills/docs/superpowers/plans/2026-06-30-codex.md:470), [plan:496](/Users/rkuprin/claude-skills/docs/superpowers/plans/2026-06-30-codex.md:496)). In this environment, writable roots do not include `~/.codex` or `~/.claude`. Either the plan needs an explicit user/manual install step, or it must run in an environment with those writes permitted.

2. **“Auto hook” is overstated.**  
   The spec says the spec→plan transition is “on by default, auto-run” via `~/.claude/CLAUDE.md` plus skill description ([spec:195](/Users/rkuprin/claude-skills/docs/superpowers/specs/2026-06-30-codex-design.md:195), [plan:508](/Users/rkuprin/claude-skills/docs/superpowers/plans/2026-06-30-codex.md:508)). That is not a real hook; it is an instruction Claude may follow. If deterministic gating matters, call it a convention/manual policy, or use an actual automation surface. As written, failures will be silent: Claude can forget, misclassify the transition, or skip it under context pressure.

3. **Task 1 can destroy or misclassify user global instructions.**  
   The plan blindly copies `~/.codex/AGENTS.md` into `CHARTER.md` and moves it to `.bak` ([plan:36](/Users/rkuprin/claude-skills/docs/superpowers/plans/2026-06-30-codex.md:36)). If the file already contains any personal instructions mixed with the charter, they become part of the reviewer charter. If `.bak` already exists, it risks overwrite/loss. Add an explicit content check, preserve existing backup with a timestamp, and require user confirmation if the file is not exactly the expected charter.

4. **The charter verification looks wrong.**  
   The planned check searches for `^Your loyalty is to being right` ([plan:50](/Users/rkuprin/claude-skills/docs/superpowers/plans/2026-06-30-codex.md:50)). The charter text provided in this run uses the heading `## Your loyalty to being right, not to a role`, so that check will fail against the intended content.

5. **The acceptance test does not actually test the skill UX.**  
   Task 8 calls `run-codex.sh` directly with a prewritten prompt ([plan:571](/Users/rkuprin/claude-skills/docs/superpowers/plans/2026-06-30-codex.md:571)). It does not prove `/codex` asks for a goal, parses `--effort`, composes context correctly, or that Claude relays/weighs the result. That is wrapper acceptance, not skill acceptance.

6. **The pylox.io end-to-end target is incoherent for reviewing this repo.**  
   Task 8 runs Codex with `--repo ~/pylox.io` while asking it to read specs under `~/claude-skills` ([plan:559](/Users/rkuprin/claude-skills/docs/superpowers/plans/2026-06-30-codex.md:559)). If Codex’s sandbox limits file access to the working root, the reviewer cannot read the artifacts. For this review, run in `~/claude-skills`, or pass/copy artifacts into the target repo, or add the source repo explicitly if the CLI/sandbox supports that safely.

7. **The data-access acceptance is too vague to validate.**  
   “Choose one concrete claim at runtime” ([plan:577](/Users/rkuprin/claude-skills/docs/superpowers/plans/2026-06-30-codex.md:577)) is not an acceptance test. Name the actual table/column/count/nullability claim before implementation, and define what proves read-only access worked. Otherwise “Codex said it needed access” can accidentally pass a criterion that was supposed to prove DB verification.

What is sound:

- The overlay design is the right direction: scoped `CODEX_HOME`, `AGENTS.md -> CHARTER.md`, symlinked `auth.json`/`config.toml`, and no charter text in the prompt ([spec:40](/Users/rkuprin/claude-skills/docs/superpowers/specs/2026-06-30-codex-design.md:40), [spec:163](/Users/rkuprin/claude-skills/docs/superpowers/specs/2026-06-30-codex-design.md:163)).
- Local CLI checks confirm `codex exec` rejects `--ask-for-approval`, and `codex exec resume` rejects `--sandbox` and `-C`, so the plan’s corrections there are right.
- Local config currently has `model = "gpt-5.5"`, and official OpenAI docs currently list “Latest: GPT-5.5”. Still, the durable design should say “inherit configured model” and avoid baking in “current strongest” claims except in dated notes.

I would proceed after tightening those points. The core mechanism is worth building; the plan needs to separate repo-tracked implementation from user-home installation, downgrade “hooks” to non-deterministic instructions unless real automation is added, and make acceptance tests prove the actual `/codex` skill behavior rather than only the wrapper.

## Rebuttal round (resume — same thread)

_Claude conceded #2–#7 + #3 hardening, pushed back on #1 (Codex had read its own sandbox), and asked Codex to empirically test read scope. Reply:_

Yes, your clarification resolves my #1 as a blocker. I would rephrase it as a required-permissions note, not a design flaw: “implementation/install steps are run by Claude in the user’s normal session and require write access to `~/.codex`, `~/.claude`, and this repo; Codex reviewer runs are separate and sandboxed.” Residual risk: user-home mutation is still sensitive, so keep the content check, timestamped backup, and clear rollback.

Empirical read test: workspace-write here does **not** restrict reads to the working root. From `/Users/rkuprin/claude-skills`, I could read:

- `/etc/hosts`
- `$HOME/.codex/config.toml` existence and a non-secret model line
- a temp file outside the repo

So #6 should be softened. Original `~/pylox.io` rooting was suboptimal and potentially confusing, not necessarily broken by read scope. The stronger reason to root at `~/claude-skills` for the gap review is correctness of working context: git status, repo-relative paths, AGENTS/project instructions, and shell defaults all point at the artifacts under review. For the data pass, rooting at `~/pylox.io` remains right because the repo-local tooling/data access belongs there.