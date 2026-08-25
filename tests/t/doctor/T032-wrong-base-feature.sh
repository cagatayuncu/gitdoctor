#!/usr/bin/env bash
. "$(dirname "$0")/../../lib/harness.sh"

mkrepo
commit_file m.txt "feat: only on main"
git push -q origin main
git switch -qc feature/oops main
commit_file feat.txt "feat: work"
git push -qu origin feature/oops

run_doctor --checks wrong-base-feature,missing-back-merge,back-merge-content-only
assert_finding wrong-base-feature warning
assert_data wrong-base-feature '"branch":"feature/oops"'
assert_data wrong-base-feature '"mainOnlyCommits":1'
assert_data wrong-base-feature '"relatedFinding":"missing-back-merge"'

# recipe: rebase the branch onto develop, then update the remote
BASE=$(git merge-base origin/main feature/oops)
git rebase -q --onto origin/develop "$BASE" feature/oops
git push -qf origin feature/oops
run_doctor --checks wrong-base-feature,missing-back-merge,back-merge-content-only
assert_no_finding wrong-base-feature
