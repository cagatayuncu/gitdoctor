#!/usr/bin/env bash
. "$(dirname "$0")/../../lib/harness.sh"

mkrepo
use_gh_stub

run_doctor_gh --checks gh-protection-missing-develop
assert_finding gh-protection-missing-develop info
assert_data gh-protection-missing-develop '"branch":"develop"'

# protected develop clears the finding and resolves its merge mode to pr
stub_set protection-develop.txt true
run_doctor_gh --checks gh-protection-missing-develop
assert_no_finding gh-protection-missing-develop
grep -q '"develop":"pr"' "$TESTTMP/out.jsonl" || fail "expected resolved mergeMode pr for protected develop"

# API error (empty answer) -> skipped, never a false finding
stub_set protection-develop.txt ""
run_doctor_gh --checks gh-protection-missing-develop
assert_skipped gh-protection-missing-develop api-error

# offline -> skipped like every gh check
run_doctor --checks gh-protection-missing-develop
assert_skipped gh-protection-missing-develop offline
