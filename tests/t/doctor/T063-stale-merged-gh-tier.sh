#!/usr/bin/env bash
. "$(dirname "$0")/../../lib/harness.sh"

# gh authoritatively reports feature/x merged even though ancestry and content
# say otherwise (e.g. a squash-merge followed by more develop churn).
mkrepo
git switch -qc feature/x develop
commit_file fx.txt "feat: x"
git push -qu origin feature/x
MERGED_HEAD=$(git rev-parse HEAD)
git switch -q develop
use_gh_stub
stub_set merged-heads.txt "feature/x $MERGED_HEAD"

run_doctor_gh --checks branch-stale-merged
assert_finding branch-stale-merged info
assert_data branch-stale-merged '"method":"gh-pr"'

# The name alone proves nothing: a branch name reused after its PR merged (a
# new PR on the same name, e.g. gitdoctor's own backmerge/main carrier) has
# moved past the merged head. Flagging it would prescribe `git branch -D` for
# unmerged work.
git switch -q feature/x
commit_file fx2.txt "feat: x again, new PR"
git push -q origin feature/x
git switch -q develop
run_doctor_gh --checks branch-stale-merged
assert_no_finding branch-stale-merged

# a merged head this clone has never seen: not proof either
stub_set merged-heads.txt "feature/x 1111111111111111111111111111111111111111"
run_doctor_gh --checks branch-stale-merged
assert_no_finding branch-stale-merged

# one of several PRs on the same name merged exactly this tip: stale again
stub_set merged-heads.txt "feature/x 1111111111111111111111111111111111111111" "feature/x $(git rev-parse feature/x)"
run_doctor_gh --checks branch-stale-merged
assert_finding branch-stale-merged info
