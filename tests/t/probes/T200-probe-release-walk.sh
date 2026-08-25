#!/usr/bin/env bash
. "$(dirname "$0")/../../lib/harness.sh"

# Walk a local-mode release finish halfway, assert the probe reports exactly
# the right done/pending split, then finish and assert all-done.
mkrepo
git switch -qc release/1.2.0 develop
commit_file rel.txt "chore(release): 1.2.0"
git push -qu origin release/1.2.0

# nothing merged yet
run_probe --probe finish-release --branch release/1.2.0 --version 1.2.0
assert_step version-bumped true # no version files configured
assert_step merged-to-main false
assert_step tag-exists false
assert_step tag-pushed false
assert_step back-merged false
assert_step remote-branch-deleted false
assert_step local-branch-deleted false
assert_step gh-release false

# merge to main + tag locally, push main only (tag deliberately unpushed)
git switch -q main
git merge -q --no-ff release/1.2.0 -m "Release 1.2.0"
git tag -a v1.2.0 -m "Release 1.2.0"
git push -q origin main

run_probe --probe finish-release --branch release/1.2.0 --version 1.2.0
assert_step merged-to-main true
assert_step_data merged-to-main '"via":"ancestry"'
assert_step tag-exists true
assert_step_data tag-exists '"annotated":true'
assert_step tag-pushed false
assert_step back-merged false
assert_step remote-branch-deleted false
assert_step local-branch-deleted false

# finish the walk: push tag, back-merge the tag, delete branches
git push -q origin v1.2.0
git switch -q develop
git merge -q --no-ff v1.2.0 -m "Back-merge release 1.2.0"
git push -q origin develop
git push -q origin --delete release/1.2.0
git branch -qd release/1.2.0

run_probe --probe finish-release --branch release/1.2.0 --version 1.2.0
assert_step version-bumped true
assert_step merged-to-main true
assert_step tag-exists true
assert_step tag-pushed true
assert_step back-merged true
assert_step_data back-merged '"mode":"ancestry"'
assert_step remote-branch-deleted true
assert_step local-branch-deleted true
assert_step gh-release false # offline: gh unavailable
