#!/usr/bin/env bash
. "$(dirname "$0")/../../lib/harness.sh"

mkrepo
git switch -q develop
commit_file d.txt "feat: unreleased"
git push -q origin develop
git switch -qc hotfix/1.0.1 develop
commit_file fix.txt "fix: urgent"
git push -qu origin hotfix/1.0.1

run_doctor --checks wrong-base-hotfix,wrong-base-feature
assert_finding wrong-base-hotfix critical
assert_data wrong-base-hotfix '"branch":"hotfix/1.0.1"'
assert_data wrong-base-hotfix '"developOnlyCommits":1'
assert_no_finding wrong-base-feature # must not double-fire
assert_exit 2 "$DOCTOR_EXIT"

# recipe: recreate from main, cherry-pick the fix
FIX_SHA=$(git rev-parse hotfix/1.0.1)
git switch -q main
git branch -qD hotfix/1.0.1
git push -q origin --delete hotfix/1.0.1
git switch -qc hotfix/1.0.1 main
git cherry-pick "$FIX_SHA" >/dev/null
git push -qu origin hotfix/1.0.1
run_doctor --checks wrong-base-hotfix
assert_no_finding wrong-base-hotfix
