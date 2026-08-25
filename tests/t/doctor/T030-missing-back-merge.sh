#!/usr/bin/env bash
. "$(dirname "$0")/../../lib/harness.sh"

mkrepo
git switch -qc hotfix/1.0.1 main
commit "fix: crash"
git switch -q main
git merge -q --no-ff hotfix/1.0.1 -m "Hotfix 1.0.1"
git tag -a v1.0.1 -m "1.0.1"
git push -q origin main v1.0.1
git branch -qd hotfix/1.0.1 # deliberately NO back-merge, branch cleaned up

run_doctor --checks missing-back-merge,back-merge-content-only
assert_finding missing-back-merge critical
assert_data missing-back-merge '"ahead":2' # fix commit + merge commit
assert_data missing-back-merge '"patchEquivalent":false'
assert_exit 2 "$DOCTOR_EXIT"

# recipe from fix-recipes.md#missing-back-merge
git switch -q develop
git merge -q --no-ff origin/main -m "Back-merge main"
git push -q origin develop
run_doctor --checks missing-back-merge,back-merge-content-only
assert_no_finding missing-back-merge
assert_no_finding back-merge-content-only
