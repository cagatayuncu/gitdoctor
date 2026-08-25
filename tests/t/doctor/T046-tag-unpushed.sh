#!/usr/bin/env bash
. "$(dirname "$0")/../../lib/harness.sh"

mkrepo
git tag -a v1.0.0 -m local-only

run_doctor --checks tag-unpushed,tag-sha-mismatch
assert_finding tag-unpushed warning
assert_data tag-unpushed '"tag":"v1.0.0"'
assert_no_finding tag-sha-mismatch

# recipe: push the tag
git push -q origin v1.0.0
run_doctor --checks tag-unpushed,tag-sha-mismatch
assert_no_finding tag-unpushed
