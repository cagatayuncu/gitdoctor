#!/usr/bin/env bash
. "$(dirname "$0")/../../lib/harness.sh"

mkrepo
git switch -qc release/1.0.0 develop
commit_file rel.txt "chore: prep"
git push -qu origin release/1.0.0
git switch -q main
git merge -q --no-ff release/1.0.0 -m "Release 1.0.0"
git tag -a v1.0.0 -m "1.0.0"
git push -q origin main v1.0.0

run_doctor --checks orphaned-release-branch,orphaned-hotfix-branch,release-version-collision
assert_finding orphaned-release-branch warning
assert_data orphaned-release-branch '"branch":"release/1.0.0"'
assert_data orphaned-release-branch '"tag":"v1.0.0"'
assert_no_finding release-version-collision # orphan case must not double-fire collision
assert_no_finding orphaned-hotfix-branch

# recipe tail: after verifying the merge, delete the branch
git push -q origin --delete release/1.0.0
git branch -qD release/1.0.0
run_doctor --checks orphaned-release-branch,orphaned-hotfix-branch
assert_no_finding orphaned-release-branch
