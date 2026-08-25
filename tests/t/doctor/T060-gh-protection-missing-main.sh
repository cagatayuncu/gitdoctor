#!/usr/bin/env bash
. "$(dirname "$0")/../../lib/harness.sh"

mkrepo
use_gh_stub

run_doctor_gh --checks gh-protection-missing-main
assert_finding gh-protection-missing-main info

# protected main clears the finding and resolves merge mode to pr
stub_set protection-main.txt true
run_doctor_gh --checks gh-protection-missing-main
assert_no_finding gh-protection-missing-main
grep -q '"main":"pr"' "$TESTTMP/out.jsonl" || fail "expected resolved mergeMode pr for protected main"
