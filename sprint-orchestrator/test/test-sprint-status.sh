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

git worktree remove --force "$WT" 2>/dev/null
printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
