#!/usr/bin/env bash
. "$(dirname "$0")/../../lib/harness.sh"

mkrepo
git tag -a v1.1.0 -m "1.1.0"
git push -q origin v1.1.0

# lower than the latest tag -> collision
git switch -qc release/1.0.0 develop
git push -qu origin release/1.0.0
run_doctor --checks release-version-collision
assert_finding release-version-collision warning
assert_data release-version-collision '"branch":"release/1.0.0"'
assert_data release-version-collision '"latestTag":"v1.1.0"'

# equal to the latest tag also collides (tag itself does not exist for 1.1.0? it does -> orphan path)
# so use a strictly higher version to prove the negative case
git push -q origin --delete release/1.0.0
git switch -q develop
git branch -qD release/1.0.0
git switch -qc release/1.2.0 develop
git push -qu origin release/1.2.0
run_doctor --checks release-version-collision
assert_no_finding release-version-collision
