#!/usr/bin/env bash
. "$(dirname "$0")/../../lib/harness.sh"

mkrepo
use_gh_stub
stub_set open-prs.txt "12 feature/x main"

run_doctor_gh --checks gh-open-pr-wrong-base
assert_finding gh-open-pr-wrong-base warning
assert_data gh-open-pr-wrong-base '"pr":12'
assert_data gh-open-pr-wrong-base '"head":"feature/x"'

# a feature PR against develop is correct
stub_set open-prs.txt "13 feature/x develop"
run_doctor_gh --checks gh-open-pr-wrong-base
assert_no_finding gh-open-pr-wrong-base
