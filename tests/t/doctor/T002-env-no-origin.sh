#!/usr/bin/env bash
. "$(dirname "$0")/../../lib/harness.sh"

git init -q -b main "$TESTTMP/repo"
cd "$TESTTMP/repo"
commit "chore: root"
git branch develop
run_doctor --checks env-no-origin,env-missing-main,env-missing-develop
assert_finding env-no-origin critical
assert_no_finding env-missing-main
assert_no_finding env-missing-develop
assert_exit 2 "$DOCTOR_EXIT"
