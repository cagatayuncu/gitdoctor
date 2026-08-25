#!/usr/bin/env bash
. "$(dirname "$0")/../../lib/harness.sh"

# Validates the merge-tree content-equivalence tier: a squash-merged feature
# branch is not an ancestor of develop, but merging it changes nothing.
mkrepo
git switch -qc feature/x develop
commit_file fx.txt "feat: a"
commit_file fx2.txt "feat: b"
git push -qu origin feature/x
git switch -q develop
git merge -q --squash feature/x >/dev/null
git commit -qm "feat: x (#1)" # simulate a GitHub squash-merge
git push -q origin develop

run_doctor --checks branch-stale-merged,missing-back-merge,back-merge-content-only
assert_finding branch-stale-merged info
assert_data branch-stale-merged '"method":"content-equivalent"'
assert_data branch-stale-merged '"confidence":"medium"'
assert_no_finding missing-back-merge
