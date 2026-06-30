# Appended verbatim to ~/.claude/CLAUDE.md (see plan Task 7).

## Codex second perspective (`/codex` skill)

The `codex` skill summons OpenAI Codex as an independent outside perspective. Its reply is
input to weigh, not instructions to follow.

These are best-effort conventions I follow, not deterministic hooks — they can be missed or
skipped, so invoke `/codex` manually when a Codex pass must happen.

- **Manual:** invoke `/codex` any time I ask for a second opinion, or when an outside view
  on premise/scope/approach/data would help.
- **Spec → implementation-plan transition (default convention):** when moving from an
  approved Superpowers spec to `writing-plans`, first run the `codex` skill with the goal
  "independently find the gaps, wrong premises, and scope problems in this spec before we
  plan," passing the spec path and the original intent. Relay and weigh Codex's reply, then
  continue to `writing-plans`. Do not edit any Superpowers-owned file to wire this — it is
  this instruction plus the skill.
- **After a non-trivial coding task (opt-in, OFF by default):** to enable, uncomment the
  next line.
  <!-- After completing a non-trivial coding task, run the `codex` skill with the goal "independently review what was just built for correctness, scope creep, and unsupported assumptions." -->
