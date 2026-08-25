#!/usr/bin/env bash
. "$(dirname "$0")/../../lib/harness.sh"

mkrepo
git switch -qc feature/done develop
commit_file f2.txt "feat: done"
git push -qu origin feature/done
git switch -q develop
git merge -q --no-ff feature/done -m "merge feature/done"
git push -q origin develop

run_doctor --checks branch-stale-merged,branch-stale-inactive
assert_finding branch-stale-merged info
assert_data branch-stale-merged '"method":"ancestry"'
assert_no_finding branch-stale-inactive

# recipe: delete local + remote
git push -q origin --delete feature/done
git branch -qd feature/done
run_doctor --checks branch-stale-merged,branch-stale-inactive
assert_no_finding branch-stale-merged
