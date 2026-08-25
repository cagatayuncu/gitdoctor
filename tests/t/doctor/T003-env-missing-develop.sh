#!/usr/bin/env bash
. "$(dirname "$0")/../../lib/harness.sh"

git init -q --bare -b main "$TESTTMP/origin.git"
git init -q -b main "$TESTTMP/repo"
cd "$TESTTMP/repo"
git remote add origin "$TESTTMP/origin.git"
commit "chore: root"
git push -q origin main
run_doctor --checks env-missing-develop,env-missing-main,missing-back-merge
assert_finding env-missing-develop critical
assert_no_finding env-missing-main
assert_skipped missing-back-merge missing-main-or-develop
assert_exit 2 "$DOCTOR_EXIT"

# fix: create develop
git branch develop
git push -q origin develop
run_doctor --checks env-missing-develop,env-missing-main,missing-back-merge
assert_no_finding env-missing-develop
