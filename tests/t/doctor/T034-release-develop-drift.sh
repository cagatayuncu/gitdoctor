#!/usr/bin/env bash
. "$(dirname "$0")/../../lib/harness.sh"

mkrepo
git switch -qc release/1.0.0 develop
commit_file rel.txt "chore: release prep"
git push -qu origin release/1.0.0
git switch -q develop
commit_file d.txt "feat: next iteration"
git push -q origin develop

run_doctor --checks release-develop-drift
assert_finding release-develop-drift info
assert_data release-develop-drift '"developAhead":1'
assert_data release-develop-drift '"pendingBackMerge":1'
assert_data release-develop-drift '"conflictsPredicted":false'

# an add/add clash on develop upgrades the severity via merge-tree prediction
printf 'clash\n' >rel.txt
git add rel.txt
git commit -qm "feat: clashing file"
git push -q origin develop
run_doctor --checks release-develop-drift
assert_finding release-develop-drift warning
assert_data release-develop-drift '"conflictsPredicted":true'
