# Phase 0 probe results — Claude watch transport

**Date:** 2026-07-23 · **Machine:** macOS, Claude Code v2.1.218, session permission mode
`defaultMode: "auto"` · **Probe rig:** live interactive main session (the implementing
session), scratch repos under the session scratchpad, `SPRINT_MAIL_ROOT` overridden,
real `sprint-mail.sh watch` (Task 1 build) under both launchers.

## Decision

**Monitor (persistent: true) confirmed as the primary launcher; Bash
`run_in_background` confirmed as a working fallback.** Matches the spec's revised
decision rule — both passed idle re-invocation and unattended re-arm; Monitor keeps
primacy on the documented-semantics and longevity evidence already recorded in the
spec's review addendum.

## Experiments

| # | Experiment | Launcher | Result |
|---|-----------|----------|--------|
| 1 | Idle wake: mail lands 60s after turn end | Monitor | **PASS** — event re-invoked the model with no operator input. Post at t0+60, watch woke one poll later (+2s). Wake line + exit echo delivered as ONE batched event → ONE model turn (no duplicate turn from line-then-exit). Exit→first-tool-action ≈36s (includes model turn startup). Lock removed on exit. |
| 2 | Timeout wake (30s, reply glob) | Monitor | **PASS** — exit-1 guidance line delivered, correct per-glob text (executor no-reply fallback). |
| 3 | Unattended re-arm immediately on wake | Monitor | **PASS** — new Monitor launched in the wake turn with zero prompts, zero operator input. |
| 4 | Wake-on-exit | Bash run_in_background | **PASS** — completion notification delivered (exited mid-turn; queued to the turn boundary). Note: the harness reports the COMMAND's exit (echo masks watch's exit code); the watch line itself is in the task output. |
| 5 | Idle re-invocation | Bash run_in_background | **PASS** — 25s-timeout watch completion re-invoked the model from idle. |
| 6 | Mid-turn delivery | Monitor | **PASS (queued)** — watch exited while the model was mid-turn; event delivered at the next turn boundary. Not dropped, does not interrupt. |
| 7 | Three simultaneous completions (posts within ~1s, three worktrees) | Monitor ×3 | **PASS** — all three events delivered in one re-invocation, individually labeled, none lost. |
| 8 | Lock hygiene | both | **PASS** — locks removed on wake and timeout exits (probe observations + Task 1 unit tests for dead-PID prune, age backstop, conflict refusal). |

## Permission rule

This machine runs `defaultMode: "auto"` (user settings.json) — no explicit allow rule
was needed for any launch, including unattended re-arms. For a stricter posture, the
exact-command rule form is:

```
Bash(~/.claude/skills/sprint-orchestrator/sprint-mail.sh watch:*)
```

(match the literal rendered command — the skills symlink path, not the repo path; add
the repo-path variant `Bash(/Users/rkuprin/claude-skills/sprint-orchestrator/sprint-mail.sh watch:*)`
if any prose renders it that way). Monitor is governed by the same Bash rules
(documented), so one rule covers both launchers.

## Residuals

- **3h longevity:** a Monitor watch with the full 10800s budget was started mid-probe
  (task `btgtdc2cg`, sprint `probe-longevity`) and left running through implementation;
  outcome recorded at Task 8. If unproven there, confirm on the first production wave.
  A ≥1h observation window is expected within this session.
- **Esc / session close / resume:** not locally probed (disruptive to the implementing
  session). Documented behavior stands: monitors are never restored on resume; an
  abandoned monitor may surface an orphan notice. The design absorbs both — the
  per-turn sweep catches missed wakes, and "no live watch → sweep, then re-park" is
  pinned in prose. Verify opportunistically at the first natural session boundary.
- Delivery latency beyond this machine's ≈36s observation: community reports up to
  ~85s exist; acceptance criterion is unchanged (eventually drains the durable mailbox
  without polling or blocking — the sweep, not the wake, is authoritative).
