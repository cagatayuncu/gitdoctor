#!/usr/bin/env bash
. "$(dirname "$0")/../../lib/harness.sh"

# A release branch that already shipped (tag on main) but was never deleted is
# a leftover, not an open release: it must not hijack the hotfix back-merge.
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
git push -q origin develop
git push -q origin --delete release/1.0.0 # leftover: local only, already on main

git switch -qc hotfix/1.0.1 main
commit_file fix.txt "fix: urgent"
git push -qu origin hotfix/1.0.1
git switch -q main
git merge -q --no-ff hotfix/1.0.1 -m "Hotfix 1.0.1"
git tag -a v1.0.1 -m "1.0.1"
git push -q origin main v1.0.1

run_probe --probe finish-hotfix --branch hotfix/1.0.1 --version 1.0.1
assert_step merged-to-main true
assert_step back-merged false
assert_step_data back-merged '"target":"develop"'
assert_step_data back-merged 'already shipped'

# completing the develop back-merge closes the walk
git switch -q develop
git merge -q --no-ff v1.0.1 -m "Back-merge hotfix 1.0.1"
git push -q origin develop
run_probe --probe finish-hotfix --branch hotfix/1.0.1 --version 1.0.1
assert_step back-merged true
assert_step_data back-merged '"target":"develop"'
