#!/usr/bin/env bash
. "$(dirname "$0")/../../lib/harness.sh"

# gh authoritatively reports feature/x merged even though ancestry and content
# say otherwise (e.g. a squash-merge followed by more develop churn).
mkrepo
git switch -qc feature/x develop
commit_file fx.txt "feat: x"
git push -qu origin feature/x
git switch -q develop
use_gh_stub
stub_set merged-heads.txt "feature/x"

run_doctor_gh --checks branch-stale-merged
assert_finding branch-stale-merged info
assert_data branch-stale-merged '"method":"gh-pr"'
