#!/usr/bin/env bash
# test-sprint-status.sh — each case reproduces a real misreport observed in ~/lead-us.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SUT="$HERE/../sprint-status.sh"
PASS=0; FAIL=0
ok() { PASS=$((PASS+1)); printf 'ok   - %s\n' "$1"; }
no() { FAIL=$((FAIL+1)); printf 'FAIL - %s\n' "$1"; }
# assert that story $2 has state $3 in the output $1
state_is() {
  local out="$1" num="$2" want="$3" got
  got="$(printf '%s\n' "$out" | awk -v n="$num" '$2==n {print $1}')"
  [ "$got" = "$want" ] && ok "story $num is $want" || no "story $num: want $want, got '${got:-<absent>}'"
}

REPO="$(mktemp -d)"; cd "$REPO"
git init -q -b main
git config user.email t@t; git config user.name t
SD="docs/sprints/s"; mkdir -p "$SD"
for f in 00-overview 01-alpha 02-beta 03-gamma 06-zeta 06b-delta; do echo "# $f" > "$SD/$f.md"; done
echo "# feedback" > "$SD/STORY-FEEDBACK.md"
git add -A && git commit -q -m "chore: seed sprint"

# Story 01 — DONE via trailer, branch deleted after a fast-forward merge.
# Regression: a deleted branch previously read TODO (lead-us stories 01 and 04).
git switch -qc sprint/01-alpha
echo work > a.txt && git add a.txt
git commit -q -m "$(printf 'feat: alpha\n\nStory: 01\nSprint: s\n')"
git switch -q main && git merge -q --ff-only sprint/01-alpha && git branch -qD sprint/01-alpha

# Story 02 — DOING: branch cut, zero commits, trunk then advances.
# Regression: this previously read DONE the moment trunk moved (lead-us story 10).
git branch sprint/02-beta main
echo more > b.txt && git add b.txt && git commit -q -m "chore: advance trunk"

# Story 03 — DONE via trailer, but a worktree still lingers on its merged branch.
# Regression: "worktree implies DOING" previously misreported this (lead-us story 07).
git switch -qc sprint/03-gamma
echo work > c.txt && git add c.txt
git commit -q -m "$(printf 'feat: gamma\n\nStory: 03\nSprint: s\n')"
git switch -q main && git merge -q --no-ff -m "Merge story 03" sprint/03-gamma
WT="$(mktemp -d)/wt03"
git worktree add -q "$WT" sprint/03-gamma

# Story 06b — DONE via trailer `Story: 06b`, merged to trunk. This is the `$`
# anchor proof: without the trailing `$` in the grep pattern, `--grep="^Story: 06"`
# matches this `Story: 06b` trailer, and story 06 below would falsely read DONE.
# Also proves the old [0-9][0-9]-*.md glob bug is gone — 06b must be enumerated at all.
git switch -qc sprint/06b-delta
echo work > d.txt && git add d.txt
git commit -q -m "$(printf 'feat: delta\n\nStory: 06b\nSprint: s\n')"
git switch -q main && git merge -q --ff-only sprint/06b-delta

# Story 06 — TODO: no commit, no branch. Must NOT be satisfied by the
# `Story: 06b` trailer above.

OUT="$(SPRINT_TRUNK=main "$SUT" "$SD" 2>&1)"
printf '%s\n' "$OUT"
echo "---"

FAIL_BEFORE=$FAIL
state_is "$OUT" 01  DONE
state_is "$OUT" 02  DOING
state_is "$OUT" 03  DONE
state_is "$OUT" 06  TODO
state_is "$OUT" 06b DONE

# 00-overview and STORY-FEEDBACK must never appear as stories. Only meaningful once
# the run above actually produced the expected story rows — otherwise a shell error
# like "No such file or directory" would vacuously satisfy both checks.
if [ "$FAIL" -eq "$FAIL_BEFORE" ]; then
  case "$OUT" in *overview*) no "00-overview excluded";; *) ok "00-overview excluded";; esac
  case "$OUT" in *FEEDBACK*) no "STORY-FEEDBACK excluded";; *) ok "STORY-FEEDBACK excluded";; esac
else
  no "00-overview excluded (skipped: story rows above did not match)"
  no "STORY-FEEDBACK excluded (skipped: story rows above did not match)"
fi

# Usage errors exit 2.
SPRINT_TRUNK=main "$SUT" >/dev/null 2>&1; [ $? -eq 2 ] && ok "no args exits 2" || no "no args exits 2"
SPRINT_TRUNK=main "$SUT" /nonexistent >/dev/null 2>&1; [ $? -eq 2 ] && ok "bad dir exits 2" || no "bad dir exits 2"
SPRINT_TRUNK=nosuchref "$SUT" "$SD" >/dev/null 2>&1; [ $? -eq 2 ] && ok "bad trunk exits 2" || no "bad trunk exits 2"

# Story 07 — legacy `.CLAIMED` doc name, branch cut, zero commits.
# Regression: `basename "$doc" .md` left `.CLAIMED` on the slug, so the branch
# lookup went looking for `sprint/07-eta.CLAIMED`, which cannot exist, and every
# legacy claimed story misreported TODO (lead-us story 10).
CD="docs/sprints/claimed-only"; mkdir -p "$CD"
echo "# 07-eta" > "$CD/07-eta.CLAIMED.md"
git add -A && git commit -q -m "chore: seed claimed-suffix fixture"
git branch sprint/07-eta main

CERR="$(mktemp)"
COUT="$(SPRINT_TRUNK=main "$SUT" "$CD" 2>"$CERR")"
CERRTXT="$(cat "$CERR")"
EXPECT_WARN="sprint-status: 1 doc still carries the legacy .CLAIMED suffix; state is derived now — rename it to NN-slug.md"

CFAIL_BEFORE=$FAIL
state_is "$COUT" 07 DOING
[ "$CERRTXT" = "$EXPECT_WARN" ] && ok "warning names count and reason" || no "warning names count and reason (got: '$CERRTXT')"

# stdout must never carry the .CLAIMED warning — only meaningful once the run above
# actually produced story 07's row (else an empty $COUT from a missing script would
# vacuously satisfy this too).
if [ "$FAIL" -eq "$CFAIL_BEFORE" ]; then
  case "$COUT" in *CLAIMED*) no "stdout stays clean of the warning";; *) ok "stdout stays clean of the warning";; esac
else
  no "stdout stays clean of the warning (skipped: story 07 row above did not match)"
fi

# No `.CLAIMED` docs in the original fixture -> no warning at all.
NERR="$(mktemp)"
SPRINT_TRUNK=main "$SUT" "$SD" >/dev/null 2>"$NERR"
[ -s "$NERR" ] && no "no warning when no .CLAIMED docs (got: '$(cat "$NERR")')" || ok "no warning when no .CLAIMED docs"

# --- Cross-sprint story-number collision ---
# Story numbers restart every sprint. Sprint "a"'s story 07 lands and merges;
# sprint "b"'s story 07 is never touched. Regression: querying DONE off `Story:`
# alone (ignoring `Sprint:`) made sprint b's 07 read DONE the moment sprint a's
# 07 merged, from the second sprint onward.
SDA="docs/sprints/a"; SDB="docs/sprints/b"; mkdir -p "$SDA" "$SDB"
echo "# 07-cross" > "$SDA/07-cross.md"
echo "# 07-other" > "$SDB/07-other.md"
git add -A && git commit -q -m "chore: seed cross-sprint fixture"

git switch -qc sprint/07-cross
echo work > cross.txt && git add cross.txt
git commit -q -m "$(printf 'feat: cross\n\nStory: 07\nSprint: a\n')"
git switch -q main && git merge -q --ff-only sprint/07-cross && git branch -qD sprint/07-cross

OUT_A="$(SPRINT_TRUNK=main "$SUT" "$SDA" 2>&1)"
OUT_B="$(SPRINT_TRUNK=main "$SUT" "$SDB" 2>&1)"
state_is "$OUT_A" 07 DONE
state_is "$OUT_B" 07 TODO

# --- Regex metacharacter in Story number must not match a decoy trailer ---
# Story doc `07.1-numdot.md` (num `07.1`) is never committed. A decoy commit
# carries the near-miss trailer `Story: 07x1`. An unescaped `.` in the --grep
# pattern matches any character, so `^Story: 07.1$` would wrongly match `07x1`.
SDM="docs/sprints/m"; mkdir -p "$SDM"
echo "# 07.1-numdot" > "$SDM/07.1-numdot.md"
git add -A && git commit -q -m "chore: seed num-metachar fixture"

git switch -qc sprint/decoy-num
echo work > decoy-num.txt && git add decoy-num.txt
git commit -q -m "$(printf 'feat: decoy\n\nStory: 07x1\nSprint: m\n')"
git switch -q main && git merge -q --ff-only sprint/decoy-num && git branch -qD sprint/decoy-num

OUT_M="$(SPRINT_TRUNK=main "$SUT" "$SDM" 2>&1)"
state_is "$OUT_M" "07.1" TODO

# --- Regex metacharacter in Sprint name must not match a decoy trailer ---
# Sprint dir `v1.0` never had a commit. A decoy commit carries `Story: 09` with
# the near-miss trailer `Sprint: v1x0`. An unescaped `.` in `^Sprint: v1.0$`
# would wrongly match `v1x0`.
SDN="docs/sprints/v1.0"; mkdir -p "$SDN"
echo "# 09-sprintdot" > "$SDN/09-sprintdot.md"
git add -A && git commit -q -m "chore: seed sprint-metachar fixture"

git switch -qc sprint/decoy-sprint
echo work > decoy-sprint.txt && git add decoy-sprint.txt
git commit -q -m "$(printf 'feat: decoy\n\nStory: 09\nSprint: v1x0\n')"
git switch -q main && git merge -q --ff-only sprint/decoy-sprint && git branch -qD sprint/decoy-sprint

OUT_N="$(SPRINT_TRUNK=main "$SUT" "$SDN" 2>&1)"
state_is "$OUT_N" 09 TODO

# --- Direction dossiers must not enumerate as stories ---
# dossier-NN.md is the convention BECAUSE it does not match the [0-9]*.md story
# glob. Story 09's row is the canary proving the hazard: NN-dossier.md DOES
# enumerate — if enumeration ever changes, these assertions flag it.
DD="docs/sprints/dossier-fixture"; mkdir -p "$DD"
echo "# 08-real" > "$DD/08-real.md"
echo "# dossier for 08" > "$DD/dossier-08.md"
echo "# phantom probe" > "$DD/09-dossier.md"
git add docs/sprints/dossier-fixture && git commit -q -m "chore: seed dossier fixture"
OUT_DD="$(SPRINT_TRUNK=main "$SUT" "$DD" 2>&1)"
state_is "$OUT_DD" 08 TODO
case "$OUT_DD" in *dossier-08*) no "dossier-08.md not enumerated";; *) ok "dossier-08.md not enumerated";; esac
state_is "$OUT_DD" 09 TODO

git worktree remove --force "$WT" 2>/dev/null
printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
