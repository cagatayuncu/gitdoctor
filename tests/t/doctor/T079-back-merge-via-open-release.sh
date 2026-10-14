#!/usr/bin/env bash
# A hotfix finished while release/1.1.0 is open is back-merged into that
# release (finish-hotfix.md § Back-merge target selection), not into develop.
# Its commits reach develop when the release finishes: not a critical
# missing-back-merge, and the release was not branched from main.
. "$(dirname "$0")/../../lib/harness.sh"

mkrepo
git tag -a v1.0.0 -m "1.0.0"
git push -q origin v1.0.0
git switch -q develop
commit_file d.txt "feat: next"
git push -q origin develop
git switch -qc release/1.1.0 develop
git push -qu origin release/1.1.0
git switch -qc hotfix/1.0.1 main
commit_file h.txt "fix: crash"
git switch -q main
git merge -q --no-ff hotfix/1.0.1 -m "Hotfix 1.0.1"
git tag -a v1.0.1 -m "1.0.1"
git push -q origin main v1.0.1
git branch -qd hotfix/1.0.1
git switch -q release/1.1.0
git merge -q --no-ff v1.0.1 -m "Back-merge hotfix 1.0.1"
git push -q origin release/1.1.0

CHECKS=missing-back-merge,back-merge-content-only,wrong-base-feature
run_doctor --checks "$CHECKS"
assert_finding missing-back-merge info
assert_data missing-back-merge '"ahead":2'
assert_data missing-back-merge '"carriedBy":"release/1.1.0"'
assert_data missing-back-merge '"key":"release/1.1.0"'
assert_no_finding back-merge-content-only
assert_no_finding wrong-base-feature # main-only commits arrived by merge, not by base
assert_exit 0 "$DOCTOR_EXIT"
run_doctor --checks wrong-base-feature # alone: decided without missing-back-merge's carrier
assert_no_finding wrong-base-feature

# a release branched from main is a wrong base, not a back-merge carrier
git switch -qc release/1.2.0 origin/main
commit_file r.txt "chore: prep 1.2.0"
git push -qu origin release/1.2.0
run_doctor --checks "$CHECKS"
assert_finding wrong-base-feature warning
assert_data wrong-base-feature '"branch":"release/1.2.0"'
assert_data wrong-base-feature '"mainOnlyCommits":2'
assert_finding missing-back-merge info # still carried by release/1.1.0
assert_data missing-back-merge '"carriedBy":"release/1.1.0"'
git switch -q main
git branch -qD release/1.2.0
git push -q origin --delete release/1.2.0

# abandoning the release drops the hotfix from develop's future
git branch -qD release/1.1.0
git push -q origin --delete release/1.1.0
# a baseline of the carried state (key = the release) must not mute this
run_doctor --checks "$CHECKS" --ignore-findings missing-back-merge:release/1.1.0
assert_finding missing-back-merge critical
assert_exit 2 "$DOCTOR_EXIT"
if grep -q '"carriedBy"' "$TESTTMP/out.jsonl"; then fail "carriedBy reported with no open release"; fi

# a release cut from main (not a carrier) leaves the finding critical
git switch -qc release/1.1.0 origin/main
git push -qu origin release/1.1.0
run_doctor --checks "$CHECKS"
assert_finding missing-back-merge critical
assert_finding wrong-base-feature warning
assert_data wrong-base-feature '"branch":"release/1.1.0"'
