#!/usr/bin/env bash
. "$(dirname "$0")/../../lib/harness.sh"

mkrepo
use_gh_stub

GH_STUB_FAIL=auth run_doctor_gh --checks env-gh-unavailable,gh-protection-missing-main
assert_finding env-gh-unavailable warning
assert_data env-gh-unavailable '"state":"gh-unauthenticated"'
assert_skipped gh-protection-missing-main gh-unauthenticated

# healthy auth clears it
run_doctor_gh --checks env-gh-unavailable
assert_no_finding env-gh-unavailable
