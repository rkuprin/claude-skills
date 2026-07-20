# Kimi harness adaptation — cron waits, `--target` renderer flag, three-harness prose

> **For agentic workers:** Execute task-by-task; steps use checkbox (`- [ ]`) tracking. **Tasks 1
> and 7 are NOT subagent-safe** — they are live validations in real Kimi sessions and need the
> human operator. The rest are inline-safe. **Note:** the `prune_stale` `set -e` fix that sat
> uncommitted in `sprint-orchestrator/sprint-mail.sh` is now landed (572a1f1, with regression
> test) — Task 2 builds on top of it.

**Goal:** Make Kimi Code CLI a full third harness for `sprint-orchestrator` — planner, supervisor,
and story executor — with cron-scheduled mailbox sweeps as its wait mechanism, an `arm` refusal
that redirects to them, a `--target` render override in `wave-handoffs.sh`, and all prose, lint,
and tests landing in lockstep. Zero mechanism change for Claude/Codex.

**Architecture:** Per spec `docs/superpowers/specs/2026-07-20-kimi-harness-adaptation-design.md`
(rev 2, post-Codex-gate). Kimi waits are recurring `CronCreate` nudges whose prompts run the
existing `sprint-mail.sh unread`/`seen` cursor sweep — no hook, no installer, no wait record.
`arm` stays `codex|claude` and refuses `kimi` with a redirect. The renderer's `--target` flag
overrides wait form + contract path + Launch cell per sheet. Shared lint fragment across all
rendered/refusal text: `Kimi has no Stop-hook wait`.

**Tech Stack:** Bash 3.2, coreutils only. Tests and lint are bash + `grep` (repo dialect — no YAML
parser). Kimi behaviors (cron persistence, 7-day stale, goal auto-continue, permission gating) are
as documented in Kimi's official docs and re-probed live in Task 1.

Task ordering is strict: **Task 1 (probe) first** — its outcome can amend the wait-form wording
that Tasks 3–5 embed. Tasks 2–6 each land their own lint pins in the same commit (repo rule:
pinned prose and its lint change together).

---

### Task 1: Live probe — `/goal` × parked cron wait (operator + main session)

**Outcome (2026-07-20): DONE — mechanism validated with amendments.** An active goal starves
cron delivery (fires held indefinitely through four windows); a blocked goal is the park
(continuations stop, held fires deliver immediately, `coalescedCount=3`); self-resume via
`UpdateGoal active` in the cron prompt works without user deferral; deadline judgment must use
epochs. Folded into spec rev 3 §1/§9; Tasks 3–5 embed the amended forms.

**Manual live validation, not a code change.** It produces a recorded result that can amend the
spec's §1 wait-form wording before any prose embeds it. Run in a scratch repo; never in a real
sprint.

- [ ] **Step 1: fixture.** Create a scratch git repo (e.g. `/tmp/kimi-probe`) with
  `docs/sprints/probe-sprint/` holding one toy story doc; export
  `SPRINT_MAIL_ROOT=/tmp/kimi-probe-mail` so the probe never touches real mail.
- [ ] **Step 2: arm a wait in a scratch Kimi session.** Start `kimi` in the scratch repo with the
  §2 permission posture (auto mode, or pre-approve `sprint-mail.sh`/`CronCreate`/`CronDelete`).
  Give the session a `/goal`, have it post a `question` for story 01 via
  `~/.agents/skills/sprint-orchestrator/sprint-mail.sh post`, then create the §1 executor cron
  wait (3-minute recurrence, literal deadline = post time + 1800s) and END ITS TURN.
- [ ] **Step 3: observe the park.** Does goal mode auto-continue into more work, or does the
  session idle? If it auto-continues, record exactly what it did — this decides whether the wait
  forms need a goal-handling clause (mark the goal blocked/paused while waiting, name who
  resumes it).
- [ ] **Step 4: deliver a reply.** From a separate shell, post `01-001-reply.md`
  (`sprint-mail.sh post … 01 reply`) before the deadline. On the next cron fire: does the session
  wake, run `unread`, read, `seen`, delete the cron task, and continue the goal to completion?
- [ ] **Step 5: deadline path.** Repeat with no reply; confirm the mtime-vs-deadline check takes
  the contract fallback after 1800s (use a short 120s budget for the probe) and self-deletes.
- [ ] **Step 6: record and amend.** Write the outcome into this plan's commit body. If any
  observation contradicts the spec's §1 forms, amend
  `docs/superpowers/specs/2026-07-20-kimi-harness-adaptation-design.md` first and carry the
  amended wording into Tasks 3–5.

### Task 2: `sprint-mail.sh` — the kimi arm refusal

- [ ] **Step 1: guard.** In the `--harness` case (currently `codex|claude) ;;`), add before the
  generic error:
  ```bash
  kimi) err "arm refuses kimi — Kimi has no Stop-hook wait; a Kimi session waits via a recurring cron sweep (see the kickoff's Mailbox wait line or sprint-orchestrator/SKILL.md 'Supervising the Wave')" ;;
  ```
  Leave the `codex|claude` acceptance, the generic error, and the `prune_stale` line (pre-existing
  uncommitted fix) untouched.
- [ ] **Step 2: header comment.** One line: Kimi sessions do not arm — they wait via recurring
  cron sweeps (see sprint-orchestrator/SKILL.md). Usage lines stay `arm --harness <codex|claude>`.
- [ ] **Step 3: test.** Add to `sprint-orchestrator/test/test-sprint-mail.sh`: `arm --harness kimi`
  exits 2, stderr matches `Kimi has no Stop-hook wait`, and `$MAIL_ROOT/.codex-waits/` gains no
  record.
- [ ] **Step 4: lint pins (same commit).**
  ```bash
  has   "mail: arm refuses kimi with redirect"  "Kimi has no Stop-hook wait" "$SMAIL"
  hasnt "mail: no kimi hook installer"          "install-kimi-hook"          "$SMAIL"
  ```
- [ ] **Step 5: verify.** `bash -n`, `sprint-orchestrator/test/test-sprint-mail.sh`,
  `test/lint-skills.sh`. Commit.

### Task 3: `wave-handoffs.sh` — the `--target` override

- [ ] **Step 1: arg parsing.** Accept an optional trailing `--target <codex|claude|kimi>` (args
  5–6). Usage string becomes:
  `wave-handoffs: usage: wave-handoffs.sh docs/sprints/<sprint> <wave> --topology <main-session|subagent> [--target <codex|claude|kimi>]`
  Unknown value → usage, exit 2. `--target` with `--topology subagent` → usage, exit 2.
- [ ] **Step 2: per-story resolution.** Where contract/mailwait resolve from `driver_hint` today,
  a present `--target` overrides for every story: `kimi` →
  contract `~/.agents/skills/agent-handoff/EXECUTION.md` and the kimi mailwait (Step 4);
  `codex`/`claude` → those forms for all stories. Absent → today's per-driver resolution,
  byte-identical output.
- [ ] **Step 3: Launch override.** `launch_line` takes an optional driver override: `--target
  codex|claude` forces that column; `--target kimi` prints, per story:
  `Launch: Kimi session · model per session config (tier <X> advisory — the ladder has no Kimi cell)`
- [ ] **Step 4: the kimi mailwait string** (single line, as rendered; amend per Task 1 if the
  probe changed the form):
  `you are a Kimi session — Kimi has no Stop-hook wait. Post your question and note the post time, then use your CronCreate tool to schedule a recurring check (every 3 minutes) whose prompt reads: "Sprint mailbox wait for {NN}-{SSS}-reply.md: run ` + full helper path + ` unread {SPRINT_DIR} '{NN}-{SSS}-reply.md' from the worktree. If the reply landed at or before the deadline you recorded (post time + 1800s, judged by the reply file's mtime): read it, mark it seen, delete this cron task, and continue the story. If it landed later, or the deadline has passed with no reply: delete this cron task and take the contract's no-reply fallback. Otherwise end the turn." Then END YOUR TURN — the cron nudge wakes you; never poll or background the wait.`
  Full helper path is `~/.agents/skills/sprint-orchestrator/sprint-mail.sh`; `{NN}`/`{SPRINT_DIR}`
  resolve at render, `{SSS}` stays literal.
- [ ] **Step 5: header note + phrasing sweep.** When `--target` is applied, the sheet header says
  so. Sweep the subagent-topology comment "both harness forms" → "any harness".
- [ ] **Step 6: tests.** `test-wave-handoffs.sh`: `--topology main-session --target kimi` matches
  a pinned golden block (kimi mailwait with full path + glob, `~/.agents` contract path, advisory
  Launch line, header note); `--target bogus` and `--target kimi --topology subagent` exit 2;
  default render still passes existing pins.
- [ ] **Step 7: lint pins (same commit).**
  ```bash
  has   "renderer: --target flag"     "--target <codex|claude|kimi>" "$WHS"
  has   "renderer: kimi wait form"    "Kimi has no Stop-hook wait"   "$WHS"
  hasnt "renderer: no kimi hook installer" "install-kimi-hook"       "$WHS"
  ```
- [ ] **Step 8: verify.** `bash -n`, `test-wave-handoffs.sh`, `test/lint-skills.sh`. Commit.

### Task 4: `agent-handoff` — kimi target and the fourth wait variant

- [ ] **Step 1: SKILL.md targets.** Targets line gains `kimi` (interactive Kimi CLI session); the
  "Claude Code and Codex share this skills repo" line and the target-universe sentence gain the
  third harness.
- [ ] **Step 2: contract path + Launch.** kimi targets →
  `~/.agents/skills/agent-handoff/EXECUTION.md`; Launch line renders
  `Launch: Kimi session · model per session config (tier {X} advisory — the ladder has no Kimi cell)`.
- [ ] **Step 3: Mailbox wait.** The bullet gains the kimi resolution; the template's
  `Mailbox wait:` braces gain the Task-3 kimi string as the fourth variant. Subagent fallback
  prose: "on either harness" → "on any harness".
- [ ] **Step 4: EXECUTION.md.** Mailbox section gains the kimi bullet (same cron form, mirrored);
  the subagent-never-arms line names Kimi Agent-tool subagents.
- [ ] **Step 5: lint pins (same commit).**
  ```bash
  has   "handoff: kimi contract path"  "~/.agents/skills/agent-handoff/EXECUTION.md" "$AH"
  has   "handoff: kimi wait form"      "Kimi has no Stop-hook wait"                  "$AH"
  hasnt "handoff: no kimi hook installer" "install-kimi-hook"                        "$AH"
  has   "contract: kimi wait form"     "Kimi has no Stop-hook wait"                  "$AHEXEC"
  has   "contract: kimi cron"          "CronCreate"                                  "$AHEXEC"
  hasnt "contract: no kimi hook installer" "install-kimi-hook"                       "$AHEXEC"
  ```
- [ ] **Step 6: verify.** `test/lint-skills.sh` (incl. the ladder-sync pins — untouched). Commit.

### Task 5: `sprint-orchestrator/SKILL.md` — three-harness prose

- [ ] **Step 1: frontmatter.** `description:` becomes a double-quoted scalar; invocation spelling
  reads `/sprint-orchestrator` (Claude), `$sprint-orchestrator` (Codex), or
  `/skill:sprint-orchestrator` (Kimi).
- [ ] **Step 2: status paths.** The `sprint-status.sh` examples gain
  `~/.agents/skills/sprint-orchestrator/sprint-status.sh docs/sprints/<sprint>   # Kimi`.
- [ ] **Step 3: capacity question.** Plan-session step 5 asks how Claude/Codex/Kimi capacity looks.
- [ ] **Step 4: Supervising the Wave.** After the codex/claude arm sentences (both lint-pinned —
  untouched), add the supervisor sweep form per spec §1 (full helper path, both globs, self-delete
  on wave conclusion, self-renew on the 7-day stale fire, one task per wave) plus one clause
  naming the permission preflight (unattended bash/CronCreate/CronDelete). Rework "both harnesses
  arm their sprint Stop hook" so the three mechanisms read as equals.
- [ ] **Step 5: Ownership Transfer.** Add the Kimi death clause: cron tasks persist across exit
  and revive on `kimi resume`; takeover requires the old session's cron deleted and goal
  ended/blocked, or the operator's commitment the session will never be resumed; note the
  worktree-keyed cursor race for a resumed old supervisor.
- [ ] **Step 6: Direct stories + planner handoff.** Name Kimi's Agent tool as an in-session
  subagent transport (same topology, same non-arming fallback); one clause that `/goal` is
  native on all three harnesses.
- [ ] **Step 7: lint pins (same commit).**
  ```bash
  has   "orchestrator: kimi invocation spelling" "/skill:sprint-orchestrator" "$ORCH"
  grep -q '^description: "' "$ORCH" && ok "orchestrator: description is a quoted scalar" || no "orchestrator: description is a quoted scalar"
  has   "orchestrator: kimi supervisor sweep is a recurring cron" "recurring cron" "$ORCH"
  has   "orchestrator: kimi skills-dir status path" "~/.agents/skills/sprint-orchestrator/sprint-status.sh" "$ORCH"
  has   "orchestrator: kimi death clause" "never be resumed" "$ORCH"
  hasnt "orchestrator: no kimi hook installer" "install-kimi-hook" "$ORCH"
  ```
- [ ] **Step 8: verify.** `test/lint-skills.sh`. Commit.

### Task 6: READMEs, INSTALL.md, CLAUDE.md

- [ ] **Step 1: sprint-orchestrator/README.md.** Use-it gains `/skill:sprint-orchestrator # Kimi`;
  status examples gain the `~/.agents` path; new `### Reactive waits on Kimi — nothing to install`
  (cron design, no hook/installer, wake latency = cron period, permission preflight); "Where to
  run it" gains a Kimi clause (Anthropic-model advice governs the claude/codex choice only).
- [ ] **Step 2: INSTALL.md.** Document `CLAUDE_SKILLS_DIR=~/.agents/skills ./install.sh`; state no
  hook wiring is needed for Kimi.
- [ ] **Step 3: repo README.md.** Kimi row in the install/use summary.
- [ ] **Step 4: CLAUDE.md** (the file `AGENTS.md` symlinks to). Under Frontmatter rules: Kimi
  honors `disable-model-invocation` (hidden from the model's listing; manual via `/skill:<name>`);
  `~/.agents/skills/` is the shared skills dir Kimi scans.
- [ ] **Step 5: lint pins (same commit).**
  ```bash
  has   "sprint readme: kimi invocation spelling"   "/skill:sprint-orchestrator" "$ORCH_README"
  has   "sprint readme: kimi waits need no install" "Reactive waits on Kimi"     "$ORCH_README"
  hasnt "sprint readme: no kimi hook installer"     "install-kimi-hook"          "$ORCH_README"
  has   "install guide: kimi skills dir"            "CLAUDE_SKILLS_DIR=~/.agents/skills" "$INSTALL"
  hasnt "install guide: no kimi hook installer"     "install-kimi-hook"          "$INSTALL"
  ```
- [ ] **Step 6: verify.** `test/lint-skills.sh`. Commit.

### Task 7: Operator live verification + full suite

**Manual, main session + operator.**

- [ ] **Step 1: full suite green.** `test/lint-skills.sh`, `codex/test/test.sh`,
  `sprint-orchestrator/test/test-*.sh`, `bash -n` on every touched script.
- [ ] **Step 2: manual-only load.** Fresh Kimi session → `/skill:sprint-orchestrator` loads; the
  skill stays absent from the model's auto-invocation listing.
- [ ] **Step 3: end-to-end (optional but recommended).** Scratch sprint, one `loop: direct` story
  executed by a Kimi main session: question posted, cron wake, reply seen, cron self-deleted,
  trailers on the commit, `sprint-status.sh` reads DONE after merge.
- [ ] **Step 4: record.** Outcomes into the final commit body; open follow-ups (e.g. resumed-
  session hazards on Claude/Codex arm records — spec Non-goals) noted, not built.

---

- **Lint lockstep:** every prose task carries its pins in the same commit. A pin added without
  its prose, or prose without its pin, fails the repo's own rule even when the lint passes.
- **Do not touch:** both stop-wait hooks, both installers, `agents/openai.yaml`,
  `sprint-status.sh`, and the ladder tables.
- **Mailbox namespace is cwd-derived (backlog wart A, NOT fixed here):** `sprint-mail.sh`
  namespaces the mailbox by the *caller's* git repo — a session cd'd into a submodule posts to
  a different mailbox (the 2026-07-20 story-09 incident). The Kimi cron forms say "from the
  worktree" / "from the project root": keep the probe fixture and all rendered kimi prose in
  plain, non-submodule repo layouts. The defect itself is backlog —
  `docs/superpowers/specs/2026-07-20-mailbox-namespace-and-integrity-backlog.md`.
- **If Task 1 amends the wait forms:** the amended wording propagates to Tasks 3, 4, and 5 in
  lockstep — the three render sites and EXECUTION.md must carry byte-identical forms, and the
  shared lint fragment `Kimi has no Stop-hook wait` must survive any amendment.
