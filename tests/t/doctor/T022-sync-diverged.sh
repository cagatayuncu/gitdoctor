#!/usr/bin/env bash
. "$(dirname "$0")/../../lib/harness.sh"

mkrepo
clone_other
commit_file remote.txt "feat: from another machine"
git push -q origin main

cd "$TESTTMP/repo"
commit "feat: local divergent work"
git fetch -q origin
run_doctor --checks sync-behind,sync-ahead,sync-diverged
assert_finding sync-diverged critical
assert_data sync-diverged '"ahead":1'
assert_data sync-diverged '"behind":1'
assert_exit 2 "$DOCTOR_EXIT"
