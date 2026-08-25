#!/usr/bin/env bash
. "$(dirname "$0")/../../lib/harness.sh"

mkrepo
echo "scratch" >new.txt
run_doctor --checks dirty-worktree
assert_finding dirty-worktree warning
assert_data dirty-worktree '"untracked":1'
assert_exit 1 "$DOCTOR_EXIT"

# fix: commit it
git add new.txt
git commit -qm "chore: add file"
git push -q origin main
run_doctor --checks dirty-worktree
assert_no_finding dirty-worktree
