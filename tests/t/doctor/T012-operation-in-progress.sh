#!/usr/bin/env bash
. "$(dirname "$0")/../../lib/harness.sh"

mkrepo
git switch -qc tmp develop
echo "side a" >conflict.txt
git add conflict.txt && git commit -qm "feat: side a"
git switch -q develop
echo "side b" >conflict.txt
git add conflict.txt && git commit -qm "feat: side b"
git merge -q tmp >/dev/null 2>&1 || true # leaves MERGE_HEAD behind

run_doctor --checks operation-in-progress
assert_finding operation-in-progress critical
assert_data operation-in-progress '"operation":"merge"'
assert_exit 2 "$DOCTOR_EXIT"

git merge --abort
run_doctor --checks operation-in-progress
assert_no_finding operation-in-progress
