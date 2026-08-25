#!/usr/bin/env bash
. "$(dirname "$0")/../../lib/harness.sh"

mkrepo
use_gh_stub
stub_set merge-methods.txt "false true true"
stub_set protection-develop.txt true

run_doctor_gh --checks gh-squash-only-back-merge-limitation
assert_finding gh-squash-only-back-merge-limitation info

# allowing merge commits clears it
stub_set merge-methods.txt "true true true"
run_doctor_gh --checks gh-squash-only-back-merge-limitation
assert_no_finding gh-squash-only-back-merge-limitation
