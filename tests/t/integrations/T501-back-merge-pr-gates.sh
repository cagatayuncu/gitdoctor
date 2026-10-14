#!/usr/bin/env bash
. "$(dirname "$0")/../../lib/harness.sh"

# back-merge-pr.sh opens a PR only when it is safe to: every gate below ends
# with no push and no PR.
mkrepo
use_gh_stub

# --- gates fed by a canned doctor report ------------------------------------
FAKE="$TESTTMP/fake-doctor.sh"
printf '%s\n' 'cat "$FAKE_REPORT"' 'exit "${FAKE_EXIT:-2}"' >"$FAKE"
export FAKE_REPORT="$TESTTMP/fake.jsonl"
HEADER='{"gitflowDoctor":"0.0.0","repo":{"root":"x","github":"","main":"main","develop":"develop","mergeMode":{"configured":"auto","resolved":{"main":"unknown","develop":"unknown"}},"versions":{"scheme":"semver","latestTag":"","nextHotfix":""},"prefixes":{"feature":"feature/","release":"release/","hotfix":"hotfix/","backmerge":"backmerge/"}},"summary":{"critical":1,"warning":0,"info":0,"ok":0,"skipped":0}}'

# shallow history -> low confidence: never act on it
printf '%s\n' '{"id":"missing-back-merge","severity":"critical","status":"fail","title":"t","data":{"ahead":1,"commits":["a"],"patchEquivalent":false,"conflictsPredicted":false},"fix":{"commands":[],"recipeRef":"r"},"confidence":"low"}' "$HEADER" >"$FAKE_REPORT"
GITDOCTOR_PATH=$FAKE run_bm
assert_bm_status skipped-low-confidence

# content already absorbed by a squash back-merge: nothing to open
printf '%s\n' '{"id":"back-merge-content-only","severity":"info","status":"fail","title":"t","data":{"ahead":1,"commits":["a"],"patchEquivalent":true},"fix":{"commands":[],"recipeRef":"r"},"confidence":"medium"}' "$HEADER" >"$FAKE_REPORT"
GITDOCTOR_PATH=$FAKE FAKE_EXIT=0 run_bm
assert_bm_status not-needed

# the doctor itself failed (usage error): an error, not a silent "not needed"
GITDOCTOR_PATH=$FAKE FAKE_EXIT=4 run_bm
[ "$BM_EXIT" -eq 1 ] || fail "a doctor failure must exit 1, got $BM_EXIT: $(bm_log)"

# the check could not run (single-branch checkout: no develop) -> never "not needed"
printf '%s\n' '{"id":"missing-back-merge","severity":"info","status":"skipped","title":"check skipped","data":{"reason":"missing-main-or-develop"}}' "$HEADER" >"$FAKE_REPORT"
GITDOCTOR_PATH=$FAKE FAKE_EXIT=0 GITHUB_ACTIONS=true run_bm
assert_bm_status skipped-unavailable
grep -q "::warning" "$TESTTMP/bm.out" || fail "an unavailable check must raise an Actions warning: $(bm_log)"

# git < 2.38: conflictsPredicted:false means "never predicted", not "no conflicts"
printf '%s\n' '{"id":"env-git-too-old","severity":"warning","status":"fail","title":"t","data":{"version":"2.34.1"},"fix":{"commands":[],"recipeRef":"r"},"confidence":"high"}' \
  '{"id":"missing-back-merge","severity":"critical","status":"fail","title":"t","data":{"ahead":1,"commits":["a"],"patchEquivalent":false,"conflictsPredicted":false},"fix":{"commands":[],"recipeRef":"r"},"confidence":"high"}' "$HEADER" >"$FAKE_REPORT"
GITDOCTOR_PATH=$FAKE run_bm
assert_bm_status skipped-unavailable

# not a repository: the header has no root -> error, not "not needed"
printf '%s\n' "${HEADER/\"root\":\"x\"/\"root\":\"\"}" >"$FAKE_REPORT"
GITDOCTOR_PATH=$FAKE FAKE_EXIT=0 run_bm
[ "$BM_EXIT" -eq 1 ] || fail "outside a repository must exit 1, got $BM_EXIT: $(bm_log)"

# --- gates on real repo states ----------------------------------------------
# a release is open and took the hotfix back-merge (finish-hotfix.md: the fix
# reaches develop through that release) -> no main->develop PR
git switch -q develop
commit_file d.txt "feat: next"
git push -q origin develop
git switch -qc release/1.1.0 develop
git push -q origin release/1.1.0
git switch -qc hotfix/1.0.1 main
commit_file h.txt "fix: crash"
git switch -q main
git merge -q --no-ff hotfix/1.0.1 -m "Hotfix 1.0.1"
git push -q origin main
git switch -q release/1.1.0
git merge -q --no-ff main -m "Back-merge hotfix 1.0.1"
git push -q origin release/1.1.0
run_bm
assert_bm_status skipped-release-open
[ -z "$(remote_sha backmerge/main)" ] || fail "release-open gate must not push the carrier"

# release finished and gone, but develop got a conflicting edit meanwhile:
# conflicts predicted -> report, never open (a PR conflict would be resolved
# by hand on GitHub, outside every gitdoctor guard)
git switch -q main
git push -q origin --delete release/1.1.0
git branch -qD release/1.1.0
commit "fix: on main"
git push -q origin main
git switch -q develop
commit "feat: on develop"
git push -q origin develop
run_bm
assert_bm_status skipped-conflicts
[ -z "$(remote_sha backmerge/main)" ] || fail "conflict gate must not push the carrier"

# a back-merge PR from another carrier is already open (a /gitdoctor finish
# in PR mode opened backmerge/release-X.Y.Z): reuse it, open nothing
git switch -q develop
git reset -q --hard HEAD~1
git push -q --force origin develop
stub_set open-prs.txt "7 backmerge/release-1.0.1 develop"
run_bm
assert_bm_status pr-exists
[ -z "$(remote_sha backmerge/main)" ] || fail "an open back-merge PR must not get a second carrier"
[ "$(pr_creates)" = 0 ] || fail "no PR expected while another back-merge PR is open"
