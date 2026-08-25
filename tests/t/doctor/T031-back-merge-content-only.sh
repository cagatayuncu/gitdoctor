#!/usr/bin/env bash
. "$(dirname "$0")/../../lib/harness.sh"

mkrepo
git switch -qc hotfix/1.0.1 main
commit "fix: crash"
git switch -q main
git merge -q --no-ff hotfix/1.0.1 -m "Hotfix 1.0.1"
git tag -a v1.0.1 -m "1.0.1"
git push -q origin main v1.0.1
git branch -qd hotfix/1.0.1

# squash-style back-merge: content lands in develop without ancestry
git switch -q develop
git merge -q --squash origin/main >/dev/null
git commit -qm "chore: back-merge 1.0.1 (squash)"
git push -q origin develop

run_doctor --checks missing-back-merge,back-merge-content-only
assert_no_finding missing-back-merge
assert_finding back-merge-content-only info
assert_data back-merge-content-only '"patchEquivalent":true'
