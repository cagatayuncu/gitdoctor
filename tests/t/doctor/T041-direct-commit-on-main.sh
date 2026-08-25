#!/usr/bin/env bash
. "$(dirname "$0")/../../lib/harness.sh"

mkrepo
commit_file direct.txt "fix: sneaky direct commit"
git push -q origin main

run_doctor --checks direct-commit-on-main
assert_finding direct-commit-on-main warning
assert_data direct-commit-on-main '"confidence":"medium"' # offline heuristic

# squash-landed PRs look like "subject (#N)" and are excluded offline
git commit -q --amend -m "fix: landed via PR (#42)"
git push -qf origin main
run_doctor --checks direct-commit-on-main
assert_no_finding direct-commit-on-main
