#!/usr/bin/env bash
# Hermetic tests for sprint-mail.sh — the executor↔supervisor mailbox helper.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SUT="$HERE/../sprint-mail.sh"
PASS=0; FAIL=0
ok() { PASS=$((PASS+1)); printf 'ok   - %s\n' "$1"; }
no() { FAIL=$((FAIL+1)); printf 'FAIL - %s\n' "$1"; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export SPRINT_MAIL_ROOT="$TMP/mailroot"
export SPRINT_MAIL_POLL=1

# Fixture repo (repo basename namespaces the mailbox).
REPO_A="$TMP/repo-alpha"
mkdir -p "$REPO_A" && git -C "$REPO_A" init -q
cd "$REPO_A"
SPRINT="docs/sprints/2026-07-14-fixture-sprint"

# ---- post: creates, sequences, zero-pads ----
p1="$(printf 'found a thing\n' | "$SUT" post "$SPRINT" 07 evidence -)"
[ "$(basename "$p1")" = "07-001-evidence.md" ] && ok "first post is 07-001-evidence.md" || no "first post is 07-001-evidence.md (got: $p1)"
[ -f "$p1" ] && grep -q 'found a thing' "$p1" && ok "post body written" || no "post body written"
case "$p1" in "$SPRINT_MAIL_ROOT/repo-alpha/2026-07-14-fixture-sprint/"*) ok "mail dir is root/repo/sprint" ;; *) no "mail dir is root/repo/sprint (got: $p1)" ;; esac

p2="$(printf 'which auth flow?\n' | "$SUT" post "$SPRINT" 07 question -)"
[ "$(basename "$p2")" = "07-002-question.md" ] && ok "executor counter increments across kinds" || no "executor counter increments across kinds (got: $p2)"

# ---- reply: reuses the open question's sequence ----
p3="$(printf 'use flow B\n' | "$SUT" post "$SPRINT" 07 reply -)"
[ "$(basename "$p3")" = "07-002-reply.md" ] && ok "reply reuses question sequence" || no "reply reuses question sequence (got: $p3)"
printf 'x\n' | "$SUT" post "$SPRINT" 07 reply - >/dev/null 2>&1 \
  && no "reply with no open question is rejected" || ok "reply with no open question is rejected"

# ---- note: independent supervisor counter ----
p4="$(printf 'heads up\n' | "$SUT" post "$SPRINT" 07 note -)"
[ "$(basename "$p4")" = "07-001-note.md" ] && ok "note counter is independent" || no "note counter is independent (got: $p4)"

# ---- concluded: outcome line enforced ----
printf 'no outcome here\n' | "$SUT" post "$SPRINT" 07 concluded - >/dev/null 2>&1 \
  && no "concluded without outcome rejected" || ok "concluded without outcome rejected"
p5="$(printf 'outcome: pr-ready\nPR #12\n' | "$SUT" post "$SPRINT" 07 concluded -)"
[ "$(basename "$p5")" = "07-003-concluded.md" ] && ok "concluded takes next executor sequence" || no "concluded takes next executor sequence (got: $p5)"

# ---- input validation ----
printf 'x\n' | "$SUT" post "$SPRINT" 07 shout - >/dev/null 2>&1 \
  && no "unknown kind rejected" || ok "unknown kind rejected"
printf 'x\n' | "$SUT" post "$SPRINT" '../evil' evidence - >/dev/null 2>&1 \
  && no "non-numeric story rejected" || ok "non-numeric story rejected"
printf 'x\n' | "$SUT" post "$SPRINT" 06b evidence - >/dev/null 2>&1 \
  && ok "suffixed story number accepted" || no "suffixed story number accepted"

# ---- list: mtime order, story filter, no tmp litter ----
printf 'other story\n' | "$SUT" post "$SPRINT" 03 evidence - >/dev/null
n_all="$("$SUT" list "$SPRINT" | wc -l | tr -d ' ')"
[ "$n_all" = "7" ] && ok "list shows all messages" || no "list shows all messages (got: $n_all)"
n_07="$("$SUT" list "$SPRINT" 07 | grep -c '/07-')"
[ "$n_07" = "5" ] && ok "list filters by story" || no "list filters by story (got: $n_07)"
"$SUT" list "$SPRINT" | grep -q '\.tmp' && no "no tmp files visible" || ok "no tmp files visible"

# ---- wait: hit, deterministic miss, timeout ----
w1="$("$SUT" wait "$SPRINT" "07-002-reply.md" 3)" \
  && [ "$(basename "$w1")" = "07-002-reply.md" ] \
  && ok "wait finds an existing exact name" || no "wait finds an existing exact name"
"$SUT" wait "$SPRINT" "07-009-reply.md" 2 >/dev/null 2>&1 \
  && no "wait for absent reply times out exit 1 (stale 002 reply must not match)" \
  || ok "wait for absent reply times out exit 1 (stale 002 reply must not match)"
( sleep 2; printf 'late\n' | "$SUT" post "$SPRINT" 03 question - >/dev/null ) &
w2="$("$SUT" wait "$SPRINT" "03-*-question.md" 6)" \
  && ok "wait picks up a file posted mid-wait" || no "wait picks up a file posted mid-wait"
wait

# ---- repo namespacing: same sprint name in another repo → different mailbox ----
REPO_B="$TMP/repo-beta"; mkdir -p "$REPO_B" && git -C "$REPO_B" init -q
cd "$REPO_B"
pB="$(printf 'x\n' | "$SUT" post "$SPRINT" 07 evidence -)"
[ "$(basename "$pB")" = "07-001-evidence.md" ] && ok "fresh counter in second repo" || no "fresh counter in second repo (got: $pB)"
case "$pB" in "$SPRINT_MAIL_ROOT/repo-beta/"*) ok "second repo gets its own mailbox" ;; *) no "second repo gets its own mailbox (got: $pB)" ;; esac

# ---- concurrent posts from both senders: no loss (split counters, distinct names) ----
cd "$REPO_A"
( printf 'n\n' | "$SUT" post "$SPRINT" 07 note - >/dev/null ) &
( printf 'e\n' | "$SUT" post "$SPRINT" 07 evidence - >/dev/null ) &
wait
MDIR="$SPRINT_MAIL_ROOT/repo-alpha/2026-07-14-fixture-sprint"
[ -f "$MDIR/07-002-note.md" ] && [ -f "$MDIR/07-004-evidence.md" ] \
  && ok "concurrent posts from both senders both land" \
  || no "concurrent posts from both senders both land"

# ---- sequence arithmetic survives zero-padded 008/009 (octal trap) ----
i=1; last=""
while [ "$i" -le 10 ]; do
  last="$(printf 'm%s\n' "$i" | "$SUT" post "$SPRINT" 09 evidence -)" || break
  i=$((i+1))
done
[ "$(basename "$last")" = "09-010-evidence.md" ] \
  && ok "counter passes 008/009 into 010" || no "counter passes 008/009 into 010 (got: $last)"

# ---- arm/disarm: cwd-keyed reactive-wait records for the Codex Stop hook ----
# arm refuses when the Stop hook is not wired (a record nothing consumes is a
# dead wait); give the fixture a wired CODEX_HOME first.
export CODEX_HOME="$TMP/codexhome"
mkdir -p "$CODEX_HOME"
out="$("$SUT" arm "$SPRINT" "07-009-reply.md" 900 2>&1)"; rc=$?
[ "$rc" = "2" ] && case "$out" in *install-codex-hook.sh*) true ;; *) false ;; esac \
  && ok "arm without wired Stop hook refused, names the installer" \
  || no "arm without wired Stop hook refused, names the installer (rc=$rc out=$out)"
printf '{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"bash codex-stop-wait.sh"}]}]}}\n' > "$CODEX_HOME/hooks.json"
WAITS="$SPRINT_MAIL_ROOT/.codex-waits"
rec="$("$SUT" arm "$SPRINT" "07-009-reply.md" 900)"
[ -f "$rec" ] && ok "arm writes a record and prints its path" || no "arm writes a record and prints its path (got: $rec)"
[ "$(sed -n 1p "$rec")" = "$(pwd -P)" ] && ok "arm line 1 is canonical cwd" || no "arm line 1 is canonical cwd"
[ "$(sed -n 2p "$rec")" = "$MDIR/07-009-reply.md" ] && ok "arm line 2 is the absolute mailbox glob" || no "arm line 2 is the absolute mailbox glob (got: $(sed -n 2p "$rec"))"
[ "$(sed -n 3p "$rec")" = "900" ] && ok "arm line 3 is the timeout" || no "arm line 3 is the timeout"
sed -n 4p "$rec" | grep -qE '^[0-9]+$' && ok "arm line 4 defaults to a now epoch" || no "arm line 4 defaults to a now epoch"
"$SUT" arm "$SPRINT" "07-010-reply.md" 900 >/dev/null 2>&1 \
  && no "second arm for same cwd rejected" || ok "second arm for same cwd rejected"
"$SUT" disarm "$SPRINT"
[ ! -f "$rec" ] && ok "disarm removes this cwd's record" || no "disarm removes this cwd's record"
"$SUT" arm "$SPRINT" "07-*-reply.md 07-*-note.md" 900 7777 >/dev/null \
  && rec2="$(ls "$WAITS"/wait-* 2>/dev/null | head -1)" \
  && [ "$(sed -n 2p "$rec2")" = "$MDIR/07-*-reply.md $MDIR/07-*-note.md" ] \
  && [ "$(sed -n 4p "$rec2")" = "7777" ] \
  && ok "arm accepts multiple globs unexpanded and an explicit since-epoch" \
  || no "arm accepts multiple globs unexpanded and an explicit since-epoch"
"$SUT" disarm "$SPRINT"
"$SUT" arm "$SPRINT" "sub/dir.md" 900 >/dev/null 2>&1 \
  && no "path-shaped pattern rejected" || ok "path-shaped pattern rejected"
"$SUT" arm "$SPRINT" "07-009-reply.md" "soon" >/dev/null 2>&1 \
  && no "non-numeric timeout rejected" || ok "non-numeric timeout rejected"

# ---- error paths: non-git CWD and missing file arg both exit 2 ----
mkdir -p "$TMP/nogit" && cd "$TMP/nogit"
out="$(printf 'x\n' | "$SUT" post "$SPRINT" 07 evidence - 2>&1)"; rc=$?
[ "$rc" = "2" ] && case "$out" in *"not inside a git repo"*) true;; *) false;; esac \
  && ok "post outside a git repo exits 2 with remedy" || no "post outside a git repo exits 2 with remedy (rc=$rc)"
cd "$REPO_A"
"$SUT" post "$SPRINT" 07 evidence "$TMP/absent.md" >/dev/null 2>&1; rc=$?
[ "$rc" = "2" ] && ok "missing file arg exits 2" || no "missing file arg exits 2 (rc=$rc)"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
