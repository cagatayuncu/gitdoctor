#!/usr/bin/env bash
. "$(dirname "$0")/../../lib/harness.sh"

mkdir -p "$TESTTMP/empty"
cd "$TESTTMP/empty"
run_doctor
assert_finding env-not-a-repo critical
assert_exit 2 "$DOCTOR_EXIT"
