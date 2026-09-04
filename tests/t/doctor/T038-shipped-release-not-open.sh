#!/usr/bin/env bash
. "$(dirname "$0")/../../lib/harness.sh"

# A shipped-but-undeleted release branch does not consume the open-release
# budget and does not report drift — but it is still reported as an orphan,
# with a cleanup hint that fits a local-only leftover.
mkrepo
git switch -qc release/1.0.0 develop
commit_file rel.txt "chore: prep 1.0.0"
git push -qu origin release/1.0.0
git switch -q main
git merge -q --no-ff release/1.0.0 -m "Release 1.0.0"
git tag -a v1.0.0 -m "1.0.0"
git push -q origin main v1.0.0
git switch -q develop
git merge -q --no-ff v1.0.0 -m "Back-merge release 1.0.0"
commit_file next.txt "feat: after the release"
git push -q origin develop
git push -q origin --delete release/1.0.0 # remote gone, local branch left behind

# the genuinely open one
git switch -qc release/1.1.0 develop
git push -qu origin release/1.1.0

run_doctor --checks multiple-release-branches,release-develop-drift,orphaned-release-branch
assert_no_finding multiple-release-branches # one open release, not two
assert_no_finding release-develop-drift     # develop is ahead of the leftover: irrelevant
assert_finding orphaned-release-branch warning
assert_data orphaned-release-branch '"branch":"release/1.0.0"'
assert_data orphaned-release-branch 'git branch -d release/1.0.0' # local-only hint

# with the leftover deleted, nothing is left to report
git branch -qD release/1.0.0
run_doctor --checks multiple-release-branches,release-develop-drift,orphaned-release-branch
assert_no_finding orphaned-release-branch
