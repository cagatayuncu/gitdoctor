#!/usr/bin/env bash
. "$(dirname "$0")/../../lib/harness.sh"

mkrepo
git switch -qc feature/login develop
commit_file login.txt "feat: login"
git push -qu origin feature/login

run_probe --probe finish-feature --branch feature/login
assert_step merged-to-develop false
assert_step remote-branch-deleted false
assert_step local-branch-deleted false

# merged but not yet deleted: ancestry is the evidence
git switch -q develop
git merge -q --no-ff feature/login -m "Merge feature/login into develop"
git push -q origin develop
run_probe --probe finish-feature --branch feature/login
assert_step merged-to-develop true
assert_step_data merged-to-develop '"via":"ancestry"'
assert_step remote-branch-deleted false
assert_step local-branch-deleted false

# fully finished: branch refs gone, evidence degrades to branch-gone
git push -q origin --delete feature/login
git branch -qd feature/login
run_probe --probe finish-feature --branch feature/login
assert_step merged-to-develop true
assert_step_data merged-to-develop '"via":"branch-gone"'
assert_step remote-branch-deleted true
assert_step local-branch-deleted true
if grep -q '"step":"tag-exists"' "$TESTTMP/probe.json"; then
  fail "feature probe must not have tag steps"
fi
