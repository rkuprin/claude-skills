# sprint-orchestrator

Turns raw sprint inputs — notes, PDFs, screenshots, tracker cards — into verified, independent
story handoff docs. It plans and hands off. It does not implement stories, merge branches, or
declare work done.

Pairs with [`agent-handoff`](../agent-handoff/), whose story-execution mode renders the kickoff
prompt that actually runs a story.

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

Only the current wave gets full story docs. Blocked work is deferred — story number allocated and
a stub recorded in the overview — and gets its doc at the wave checkpoint: re-invoke the skill on
the sprint directory when a wave lands, and it reassesses progress before writing the next wave.

Set `execution: autonomous` or `execution: stop-at-pr` once in `00-overview.md`. The planner copies
it into every story doc, so each doc stands alone and never has to read the overview to learn whether
it may merge.

## Read the state

Run it **from the project's repo root** — it reads that repo's git — using whichever agent's skills
directory you have. Both symlinks resolve to this same file.

```bash
cd ~/your-project
~/.claude/skills/sprint-orchestrator/sprint-status.sh docs/sprints/<sprint>
~/.codex/skills/sprint-orchestrator/sprint-status.sh  docs/sprints/<sprint>
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
| `DOING` | a `sprint/NN-*` branch or a worktree pinned to one exists, and not `DONE` |
| `TODO` | neither |

`DONE` outranks `DOING`, because merged branches and their worktrees linger long after the work lands.

Trunk defaults to `origin/main`; override with `SPRINT_TRUNK`. Stories are enumerated from
`[0-9]*.md`, skipping `00-*`, so suffixed numbers like `06b` are first-class. Exit code 2 on a bad
sprint directory or an unresolvable trunk.

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
sprint-orchestrator/test/test-sprint-status.sh   # 18 assertions, hermetic git fixtures
test/lint-skills.sh                              # invariants both skill files must hold
```

Each `sprint-status.sh` test case reproduces a state misreport observed in a real repo: a deleted
branch reading `TODO`, a zero-commit branch flipping to `DONE` when trunk advanced, a merged branch
with a lingering worktree reading `DOING`, and a cross-sprint story-number collision.
