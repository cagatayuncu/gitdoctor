#!/usr/bin/env bash
. "$(dirname "$0")/../../lib/harness.sh"

mkrepo
clone_other
commit_file remote.txt "feat: from another machine"
git push -q origin main

cd "$TESTTMP/repo"
git fetch -q origin
run_doctor --checks sync-behind,sync-ahead,sync-diverged
assert_finding sync-behind warning
assert_data sync-behind '"branch":"main"'
assert_data sync-behind '"behind":1'

# recipe from fix-recipes.md#sync-behind
git switch -q main
git merge -q --ff-only origin/main
run_doctor --checks sync-behind,sync-ahead,sync-diverged
assert_no_finding sync-behind
