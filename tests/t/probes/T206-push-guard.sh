#!/usr/bin/env bash
. "$(dirname "$0")/../../lib/harness.sh"

# --push-guard B[,B]: right before a push, compare the local tip, the
# remote-tracking ref (origin at the last fetch) and origin now (ls-remote).
# Read-only: it never fetches, so the tracking ref stays the "before" picture.
GUARD_EXIT=0
guard() { # branches
  set +e
  bash "$DOCTOR" --push-guard "$1" >"$TESTTMP/guard.json" 2>"$TESTTMP/doctor.err"
  GUARD_EXIT=$?
  set -e
}
has() { grep -qF "$1" "$TESTTMP/guard.json" || fail "guard output lacks $1: $(cat "$TESTTMP/guard.json")"; }
bare() { git -C "$TESTTMP/origin.git" "$@"; }

mkrepo

# in sync: nothing to push
guard main,develop
assert_exit 0 "$GUARD_EXIT"
has '"safe":true'
has '"branch":"main"'
has '"branch":"develop"'
has '"verdict":"already-pushed"'

# a local merge not pushed yet: the push fast-forwards
commit_file a.txt "feat: a"
guard main
assert_exit 0 "$GUARD_EXIT"
has '"movedSinceFetch":false,"verdict":"clean"'

# another client pushed exactly our commit: nothing left to push
bare fetch -q "$TESTTMP/repo" main:main
guard main
assert_exit 0 "$GUARD_EXIT"
has '"movedSinceFetch":true,"verdict":"already-pushed"'
git fetch -q origin

# another client pushed part of our work: still a fast-forward, but say so
commit_file b.txt "feat: b"
first=$(git rev-parse main)
commit_file c.txt "feat: c"
bare fetch -q "$TESTTMP/repo" "$first:refs/heads/main"
guard main
assert_exit 0 "$GUARD_EXIT"
has '"verdict":"moved-ancestor"'
git fetch -q origin && git push -q origin main

# someone else pushed a commit we do not have: STOP
tracking_before=$(git rev-parse origin/main)
clone_other
commit_file other.txt "feat: someone else"
git push -q origin main
cd "$TESTTMP/repo"
commit_file mine.txt "feat: mine"
guard main
assert_exit 1 "$GUARD_EXIT"
has '"safe":false'
has '"movedSinceFetch":true,"verdict":"moved"'
[ "$(git rev-parse origin/main)" = "$tracking_before" ] || fail "--push-guard must not fetch"

# origin unchanged, but local main no longer contains it: non-fast-forward
git fetch -q origin
git reset -q --hard HEAD~1
commit_file diverged.txt "feat: diverged"
guard main
assert_exit 1 "$GUARD_EXIT"
has '"movedSinceFetch":false,"verdict":"not-fast-forward"'

# a branch origin has never seen
git switch -qc feature/new
guard feature/new
assert_exit 0 "$GUARD_EXIT"
has '"verdict":"new-branch"'

# a branch deleted on origin since our fetch
git push -q -u origin feature/new
bare branch -qD feature/new
guard feature/new
assert_exit 1 "$GUARD_EXIT"
has '"verdict":"deleted"'

# usage: an empty list is rejected
set +e
bash "$DOCTOR" --push-guard , >/dev/null 2>&1
rc=$?
set -e
assert_exit 4 "$rc"

# a name that exists nowhere (typo): not safe to "push"
guard feature/typo
assert_exit 1 "$GUARD_EXIT"
has '"verdict":"unknown-branch"'

# origin went back: someone removed a commit on purpose; pushing would restore it
git switch -q main
git fetch -q origin && git reset -q --hard origin/main
commit_file bad.txt "feat: bad commit"
git push -q origin main
bad=$(git rev-parse main)
bare update-ref refs/heads/main "$bad~1"
guard main
assert_exit 1 "$GUARD_EXIT"
has '"movedSinceFetch":true,"verdict":"rewound"'

# origin unreachable: nothing is known, nothing is safe
git remote set-url origin "$TESTTMP/missing.git"
guard main
assert_exit 1 "$GUARD_EXIT"
has '"safe":false,"error":"git ls-remote origin failed"'
