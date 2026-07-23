# sprint-orchestrator

Turns raw sprint inputs — notes, PDFs, screenshots, tracker cards — into verified, independent
story handoff docs. It plans, dispatches, supervises the wave to conclusion, and integrates results — merging per
the story's execution mode, disposing of or rescuing problem stories, and handing planning to a
fresh session at each wave boundary. Story state stays derived from git throughout.

Pairs with [`agent-handoff`](../agent-handoff/), whose story-execution mode renders the kickoff
prompt that actually runs a story.

## Layout

The skill is built in layers, at two altitudes of prose:

- `SKILL.md` — the **constitution**: the management layer's mandate, decision rights, and
  invariants. Judgment-grade; it says why and when.
- `REFERENCE.md` — the **mechanics**: exact trailer/event formats, mailbox commands, the
  ladder, templates. Precision-grade; loaded on demand when performing the mechanical act.
- `../agent-handoff/EXECUTION.md` — the executor's contract: detailed, technical, concrete.
- `../codex/CHARTER.md` — the critic layer's disposition (question the premise, treat the
  brief as a claim to test), loaded by the critic skills on every run.

## Where to run it

Sprint orchestration is judgment-heavy, shortcut-friendly work: it prunes, reframes, and
re-scopes constantly. Run the planner on Anthropic models — **Fable** preferred, **kimi-k3** as
the capacity substitute (it sits between Fable and Sol in capability), **Opus** as the fallback.
Codex models execute stories well, but as planners they follow process too literally
to cut short what deserves cutting short. This is launch advice for you, the operator — the
running skill never checks or names its own model. On Kimi the planner seat is kimi-k3;
otherwise the advice above governs the Claude/Codex choice only.
Story-level routing is unaffected: the planner still routes each story with the tier ladder.

## Prerequisites

Only `git` and `bash`. No CLI to install, no API to authenticate.

The skill is **manual-only on both agents** — it never fires on its own:

| Agent | Guard | Where |
|---|---|---|
| Claude | `disable-model-invocation: true` | `SKILL.md` frontmatter |
| Codex | `policy.allow_implicit_invocation: false` | `agents/openai.yaml` |

Both must stay set. `test/lint-skills.sh` (at the repo root) fails if either is flipped or removed.
They are different keys because each agent reads only its own; Codex silently ignores the Claude one.

## Use it

From the project's repo root:

```bash
/sprint-orchestrator        # Claude Code
$sprint-orchestrator        # Codex
/skill:sprint-orchestrator  # Kimi
```

Paste the raw inputs. The skill verifies every candidate against the current code before believing
it, cuts what is stale or already shipped, splits the survivors by blast radius and file ownership,
and writes:

```
docs/sprints/<sprint>/
├── 00-overview.md      merge order, dependency edges, shared-file hotspots, cut items + reasons
├── STORY-FEEDBACK.md   append-only log of cross-story findings
├── 01-<slug>.md        one doc per story — a prompt for fresh investigation, not a stale spec
└── 07-<slug>.md
```

Only the current wave gets full story docs. Blocked work is deferred — story number allocated and a stub recorded in the overview — and
gets its doc at the wave checkpoint: when a wave concludes (every story DONE or DISPOSED), the
outgoing supervisor renders a planner handoff and a fresh session reassesses progress before
writing the next wave.

`loop: full` stories open with read-only investigation and an interactive brainstorm with you
before any code; `loop: direct` stories go straight to a short TDD plan. When execution findings
cross a story's boundary, the executor offers a handback: a `## REPLAN — rp-YYYYMMDD-NN-<n> — Story NN`
event appended to `STORY-FEEDBACK.md`. Direction stories (`flow: direction`) deliver an
investigation dossier (`dossier-NN.md` — the name deliberately misses the `[0-9]*.md` story glob)
plus a `## DIRECTION — …` event. Any re-invocation of the skill on the sprint dir resolves
unresolved events first, appending `## RESOLUTION — <id>` blocks — events are immutable and
append-only. After you approve the recap, the planner may also execute `loop: direct` stories
itself as worktree-isolated subagents under the same execution contract (see In-session
dispatch mechanics in REFERENCE.md); when Claude capacity is tight the same stories render as
Codex handoffs instead.

Set `execution: autonomous` or `execution: stop-at-pr` once in `00-overview.md`. The planner copies
it into every story doc, so each doc stands alone and never has to read the overview to learn whether
it may merge.

The plan is not done when the orchestrator finishes writing it — it is done when the Critic
has read it and spoken. The Critic is a different model family, summoned through the
[`codex`](../codex/) and [`claude-reviewer`](../claude-reviewer/) skills under their own
charter (`codex/CHARTER.md`), never re-described here. It reads the wave at two moments —
before dispatch (recorded as a `## REVIEW — rv-…` event, presented at the recap) and at each
wave conclusion (a retro over everything that landed, recorded as `## RETRO — rt-…` events
whose advice feeds the next planning session) — and the orchestrator may summon it on any
expensive fork in between. Both runs are cross-family (Codex reviews what Claude and Kimi
write, Claude/Kimi reviews what Codex writes) with the full sprint as context. The Critic's
advice is weighed by the orchestrator's judgment, never enforced mechanically. Codex executors
on `loop: full` stories additionally self-review their diff before handing off (EXECUTION.md
step 5).

## Read the state

Run it **from the project's repo root** — it reads that repo's git — using whichever agent's skills
directory you have. Both symlinks resolve to this same file.

```bash
cd ~/your-project
~/.claude/skills/sprint-orchestrator/sprint-status.sh docs/sprints/<sprint>
~/.codex/skills/sprint-orchestrator/sprint-status.sh  docs/sprints/<sprint>
~/.agents/skills/sprint-orchestrator/sprint-status.sh docs/sprints/<sprint>   # Kimi
```

Worth putting on your `PATH`:

```bash
ln -s ~/claude-skills/sprint-orchestrator/sprint-status.sh ~/bin/sprint-status
sprint-status docs/sprints/<sprint>
```

```
DONE   05   05-report-period-bug
DOING  07   07-date-presets
TODO   06b  06b-target-header-scale
```

Nothing is renamed and nothing is archived, so nothing can drift:

| State | Signal |
|---|---|
| `DONE` | one commit reachable from trunk carries **both** `Story: NN` and `Sprint: <sprint-dir-basename>` |
| `DOING` | the story doc's exact `branch:` exists locally, remotely, or in a worktree, and not `DONE` |
| `TODO` | neither |

`DONE` outranks `DOING`, because merged branches and their worktrees linger long after the work lands.

Trunk defaults to `origin/main`; override with `SPRINT_TRUNK`. Stories are enumerated from
`[0-9]*.md`, skipping `00-*`, so suffixed numbers like `06b` are first-class. Exit code 2 on a bad
sprint directory or an unresolvable trunk.

## Render a wave's handoffs

`sprint-status.sh` tells you what is done; `wave-handoffs.sh` (beside it) turns a wave into the sheet
you actually paste from. Given a sprint dir and a wave number, it prints — from each story doc's
frontmatter and its `/goal` line — a recap of the wave plus one ready-to-paste `agent-handoff`
(story-execution) kickoff per story, every value resolved. Redirect it to one file per wave:

```bash
~/.claude/skills/sprint-orchestrator/wave-handoffs.sh docs/sprints/<sprint> 4 --topology main-session > ~/.handoffs/<sprint>-wave4.md
```

Each kickoff mirrors `agent-handoff/SKILL.md`'s story-execution template — that skill file is the
source of truth for the shape; this script fills it in. `execution:` → the EXECUTION MODE line,
`loop:` → the planning-depth line, `driver_hint:` → the affinity default and the EXECUTION.md path
(`~/.codex` vs `~/.claude`); `tier:` + `effort:`/`orchestrate:` → the **Launch** line (model ·
effort) printed above each fenced block, resolved against the ladder in the SKILL.md files.
Capability, your explicit say, and current availability still override everything at paste time.
It expects the current frontmatter (`conversation`/`execution`/`loop`/`driver_hint`/`tier`); docs
without `tier:` render a row-B default with an explicit "tier unset" marker. Exit code 2 on a bad
sprint directory or a wave with no stories.

If `STORY-FEEDBACK.md` carries unresolved REPLAN/DIRECTION events, the script warns on stderr and
puts a matching line in the rendered recap — it renders anyway; resolving is your call.

`--topology` is required: `main-session` renders the paste sheet (every paste target is a
fresh main session); `subagent` renders kickoffs the orchestrator fires as in-session
subagents — those carry the non-arming `Mailbox wait:` (no wake can reach a subagent after
it returns), and only `loop: direct` stories render, with skips named on stderr.

## The mailbox

Executors and the supervising session exchange transient mail in
`~/.sprint-mail/<repo>/<sprint>/` via `sprint-mail.sh` (beside `sprint-status.sh`): executors
post `evidence`, one blocking `question` at a time, and a terminal `concluded` outcome on every
exit; the supervisor posts `reply` and `note`. It is never state — story state stays in the
commit trailers — and when nobody answers, everything degrades to the REPLAN handback protocol.

### Reactive waits on Codex — one-time install

Codex sessions cannot hold `sprint-mail.sh wait`'s poll loop open, so waiting is done by the
`codex-stop-wait.sh` Stop hook (beside `sprint-mail.sh`): a session posts its question, runs
`sprint-mail.sh arm --harness codex <sprint-dir> <reply-file-or-globs> 1800`, and ends its turn; the hook holds
the ending turn on the armed record and, when matching mail lands (or the wait times out),
its stderr re-enters the same thread as a continuation prompt. Validated live against
`codex exec` and Codex Desktop 0.144.x (2026-07-17).

`install.sh` does not wire hooks. Once per machine:

```bash
~/claude-skills/sprint-orchestrator/install-codex-hook.sh
```

Idempotent: it adds the entry to `~/.codex/hooks.json` (re-pointing it if the clone moved),
reads the hook's `currentHash` from `codex app-server`, writes it as `trusted_hash` into
`config.toml`, and re-queries until the hook reports `trusted`. Skipping this is not a soft
failure — untrusted hooks are skipped **silently**, so `sprint-mail.sh arm` refuses to run
until `hooks.json` references the hook, naming this installer in its error.

What the installer automates, for when the app-server RPC drifts — add to the `Stop` group of
`~/.codex/hooks.json`:

```json
{
  "type": "command",
  "command": "bash '<this-repo>/sprint-orchestrator/codex-stop-wait.sh'",
  "timeout": 1860,
  "statusMessage": "Waiting for sprint mailbox reply"
}
```

and trust it: the desktop app has no `/hooks` command, but `codex app-server` returns the
hook's `currentHash` from a `hooks/list` request, and writing that hash as
`trusted_hash` under `[hooks.state."<hooks.json path>:stop:0:<index>"]` in
`~/.codex/config.toml` is exactly what the TUI's trust flow does. Untrusted hooks are
skipped silently — if armed waits never hold, check trust first. The hash covers only the
hooks.json entry, so editing the script itself never needs re-trusting. For the no-hook
fallback (a single long foreground poll), raise `background_terminal_max_timeout` in
`config.toml` (milliseconds; default 300000).

### Reactive waits on Claude — nothing to install (main sessions)

A main-session Claude supervisor or executor waits by starting the mailbox watch as a
background task and ending its turn: `sprint-mail.sh watch <sprint-dir>
<reply-file-or-globs> [<timeout>]` as a Monitor (persistent: true; sessions without the
Monitor tool launch the same command via Bash `run_in_background: true` — supervise
prints the exact park). The watch polls the mailbox against the worktree's read-cursor
and exits with ONE line — the new-mail wake or the timeout guidance — and that event
wakes the session. The operator keeps the prompt the whole time; there is no Stop hook,
no arm record, and nothing to install (Monitor ships with Claude Code since v2.1.98).
The wake line is a nudge, never state: the woken session sweeps (`unread`/`seen`) before
acting. One watch per worktree, enforced by an advisory lock under the mailbox's
`.watch/` dir (stale when its PID is dead or its age passes 2x its timeout). Monitors
are never restored on session resume — no live watch means sweep, then re-park.
Budgets: 10800 for the supervisor idle sweep, 1800 for targeted reply waits. The
session's permission posture must allow the watch command to launch unattended —
re-parking after a wake happens with no operator present. Main sessions only: an
in-session subagent cannot be woken after it returns, so rendered subagent kickoffs
carry the non-arming fallback.

Machines that ran the retired `install-claude-hook.sh`: delete the `claude-stop-wait.sh`
Stop group from `~/.claude/settings.json` (leave co-installed Stop hooks untouched) —
the hook and installer no longer exist in this repo, and a settings entry pointing at a
deleted file errors on every Stop.

### Reactive waits on Kimi — nothing to install

Kimi has no Stop-hook wait (its hook timeout caps at 600s, fail-open), and there is no hook to
wire: a Kimi supervisor or executor waits via a **recurring cron sweep it schedules itself**
(CronCreate), then marks its goal blocked and ends its turn — an active goal's continuation
turns starve cron delivery, so the blocked state is the park. The cron prompt runs the same
`unread`/`seen` cursor sweep and self-deletes on reply, deadline, or wave conclusion. Wake
latency is the cron period (minutes, vs ~2s for the hooks); correctness is the same durable
read-cursor, so a missed fire is caught by the next one. The exact forms live in REFERENCE.md
("Mailbox mechanics") and the rendered kickoffs (`wave-handoffs.sh … --target kimi`).
One preflight: the session's permission posture must let the mailbox commands and cron
management run unattended (an auto permission mode or session-approved allow rules) — a sweep
that stalls on an approval panel wakes no one.

## The rule that makes it work

Every commit the executor makes for a story carries two trailers:

```
feat(reports): add date range presets

Story: 07
Sprint: 2026-07-07-report-delivery-sprint
```

That is the entire ledger. It rides inside a commit that has to happen anyway, so — unlike a filename
suffix someone must remember to change — it survives branch deletion, fast-forward, squash, and rebase.

**`Sprint:` must be the sprint directory's basename, verbatim.** Not a shortened form, not the
tracker's sprint title. `sprint-status.sh` matches it exactly against the directory you hand it.
Get it wrong and every story in that sprint reads `TODO` forever.

Both trailers are required because story numbers restart each sprint. Matching `Story: 07` alone
would make the next sprint's story 07 read `DONE` before anyone touched it.

## Sprints planned before this convention

Their commits have no trailers, and their history is not rewritten. `sprint-status.sh` will show
their stories as `DOING` (branches linger) or `TODO`, never `DONE`. That is expected, not a bug —
for those sprints, `00-overview.md` and `STORY-FEEDBACK.md` remain the record. The tool tells the
truth from the first sprint planned under this skill onward.

## Tests

From this repo:

```bash
sprint-orchestrator/test/test-sprint-status.sh   # hermetic git fixtures
sprint-orchestrator/test/test-wave-handoffs.sh   # renderer output pinned against the kickoff template
sprint-orchestrator/test/test-sprint-mail.sh   # mailbox helper: sequencing, replies, waits, arm/disarm
sprint-orchestrator/test/test-codex-stop-wait.sh # Codex Stop hook: wake, timeout, cursor + legacy records
test/lint-skills.sh                              # invariants both skill files must hold
```

Each `sprint-status.sh` test case reproduces a state misreport observed in a real repo: a deleted
branch reading `TODO`, a zero-commit branch flipping to `DONE` when trunk advanced, a merged branch
with a lingering worktree reading `DOING`, and a cross-sprint story-number collision.
