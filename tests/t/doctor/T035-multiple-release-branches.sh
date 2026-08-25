#!/usr/bin/env bash
. "$(dirname "$0")/../../lib/harness.sh"

mkrepo
git switch -qc release/1.0.0 develop
git push -qu origin release/1.0.0
git switch -qc release/1.1.0 develop
git push -qu origin release/1.1.0

run_doctor --checks multiple-release-branches
assert_finding multiple-release-branches warning
assert_data multiple-release-branches '"branches":["release/1.0.0","release/1.1.0"]'

# raising the configured limit clears it
run_doctor --checks multiple-release-branches --max-releases 2
assert_no_finding multiple-release-branches
