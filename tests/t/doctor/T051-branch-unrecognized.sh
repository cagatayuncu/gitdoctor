#!/usr/bin/env bash
. "$(dirname "$0")/../../lib/harness.sh"

mkrepo
git switch -qc wip-stuff develop
git push -qu origin wip-stuff
git switch -q develop

run_doctor --checks branch-unrecognized
assert_finding branch-unrecognized info
assert_data branch-unrecognized '"branch":"wip-stuff"'

# ignore globs silence it
run_doctor --checks branch-unrecognized --ignore-branches 'wip-*'
assert_no_finding branch-unrecognized
