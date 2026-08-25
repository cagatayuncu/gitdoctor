#!/usr/bin/env bash
. "$(dirname "$0")/../../lib/harness.sh"

mkrepo
commit "feat: local only"
run_doctor --checks sync-behind,sync-ahead,sync-diverged
assert_finding sync-ahead critical # unpushed commits on main are critical
assert_data sync-ahead '"branch":"main"'
assert_exit 2 "$DOCTOR_EXIT"

git push -q origin main
run_doctor --checks sync-behind,sync-ahead,sync-diverged
assert_no_finding sync-ahead
