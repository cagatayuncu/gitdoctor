#!/usr/bin/env bash
. "$(dirname "$0")/../../lib/harness.sh"

# With exactly one open release branch, the hotfix back-merge target is that
# release branch, not develop.
mkrepo
git switch -qc release/2.0.0 develop
commit_file rel.txt "chore: 2.0.0 prep"
git push -qu origin release/2.0.0

git switch -qc hotfix/1.0.1 main
commit_file fix.txt "fix: urgent"
git push -qu origin hotfix/1.0.1
git switch -q main
git merge -q --no-ff hotfix/1.0.1 -m "Hotfix 1.0.1"
git tag -a v1.0.1 -m "1.0.1"
git push -q origin main v1.0.1

run_probe --probe finish-hotfix --branch hotfix/1.0.1 --version 1.0.1
assert_step merged-to-main true
assert_step tag-exists true
assert_step tag-pushed true
assert_step back-merged false
assert_step_data back-merged '"target":"release/2.0.0"'

# back-merge the tag into the open release
git switch -q release/2.0.0
git merge -q --no-ff v1.0.1 -m "Back-merge hotfix 1.0.1"
git push -q origin release/2.0.0

run_probe --probe finish-hotfix --branch hotfix/1.0.1 --version 1.0.1
assert_step back-merged true
assert_step_data back-merged '"target":"release/2.0.0"'
assert_step_data back-merged '"mode":"ancestry"'

# a second open release makes the target ambiguous
git switch -qc release/2.1.0 develop
git push -qu origin release/2.1.0
run_probe --probe finish-hotfix --branch hotfix/1.0.1 --version 1.0.1
assert_step back-merged false
assert_step_data back-merged '"target":"ambiguous"'
