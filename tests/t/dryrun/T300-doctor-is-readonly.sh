#!/usr/bin/env bash
. "$(dirname "$0")/../../lib/harness.sh"

# The doctor's contract: reads only (plus the remote-tracking fetch). A full
# online run over a messy repo must leave every local head/tag and every
# remote ref byte-identical.
mkrepo
git switch -qc feature/wip develop
commit_file w.txt "feat: wip"
git push -qu origin feature/wip
git switch -qc hotfix/1.0.1 main
commit_file fix.txt "fix: urgent"
git switch -q main
git merge -q --no-ff hotfix/1.0.1 -m "Hotfix 1.0.1"
git tag -a v1.0.1 -m "1.0.1"
git push -q origin main v1.0.1
git tag stray-tag
echo dirty >dirty.txt

snapshot() {
  {
    git for-each-ref --format='%(refname) %(objectname)' refs/heads refs/tags
    git ls-remote origin
    git status --porcelain
  } >"$1" 2>/dev/null
}

snapshot "$TESTTMP/before.txt"
run_doctor_online
run_probe --probe finish-hotfix --branch hotfix/1.0.1 --version 1.0.1
snapshot "$TESTTMP/after.txt"

diff -u "$TESTTMP/before.txt" "$TESTTMP/after.txt" >"$TESTTMP/refs.diff" \
  || fail "doctor/probe mutated repo state: $(cat "$TESTTMP/refs.diff")"
