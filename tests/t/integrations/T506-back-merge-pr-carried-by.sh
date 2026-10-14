#!/usr/bin/env bash
. "$(dirname "$0")/../../lib/harness.sh"

# back-merge-pr.sh defers to the doctor's carriedBy: it holds back only for a
# release that took the hotfix back-merge. A release cut from main also
# contains main's tip but carries nothing (the doctor keeps the finding
# critical), so the back-merge PR is still due.
mkrepo
use_gh_stub
git tag -a v1.0.0 -m "1.0.0"
git push -q origin v1.0.0
git switch -q develop
commit_file d.txt "feat: next"
git push -q origin develop

git switch -qc hotfix/1.0.1 main
commit_file h.txt "fix: crash"
git switch -q main
git merge -q --no-ff hotfix/1.0.1 -m "Hotfix 1.0.1"
git tag -a v1.0.1 -m "1.0.1"
git push -q origin main v1.0.1
git branch -qd hotfix/1.0.1

# release/1.1.0 cut from main by mistake: contains main's tip, carries nothing
git switch -qc release/1.1.0 origin/main
commit_file r.txt "chore: prep 1.1.0"
git push -qu origin release/1.1.0
git switch -q main
run_bm
assert_bm_status pr-opened

# the sanctioned carrier: release/1.2.0 from develop took the hotfix tag
stub_set open-prs.txt ""
git push -q origin --delete backmerge/main release/1.1.0
git branch -qD release/1.1.0
git switch -qc release/1.2.0 develop
git merge -q --no-ff v1.0.1 -m "Back-merge hotfix 1.0.1"
git push -qu origin release/1.2.0
git switch -q main
git fetch -q origin --prune
run_bm
assert_bm_status skipped-release-open
grep -q "release/1.2.0" "$TESTTMP/bm.out" || fail "the skip must name the carrying release: $(bm_log)"
