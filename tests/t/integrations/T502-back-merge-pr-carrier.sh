#!/usr/bin/env bash
. "$(dirname "$0")/../../lib/harness.sh"

# back-merge-pr.sh vs. what people do on GitHub: fork PRs, "Update branch" on
# the back-merge PR, a merged PR whose carrier was kept. The carrier is never
# rewritten, and a dry run always agrees with the real run.
mkrepo
use_gh_stub

hotfix_on_main() { # version file
  git switch -qc "hotfix/$1" main
  commit_file "$2" "fix: $1"
  git switch -q main
  git merge -q --no-ff "hotfix/$1" -m "Hotfix $1"
  git push -q origin main
  git branch -qd "hotfix/$1"
}
git switch -q develop
commit_file d.txt "feat: next"
git push -q origin develop
git switch -q main
hotfix_on_main 1.0.1 h1.txt

# a contributor's fork PR from THEIR main into develop is not a back-merge PR
stub_set open-prs.txt "9 main develop true"
run_bm
assert_bm_status pr-opened

# a same-repo PR straight from main counts; its URL follows GITHUB_SERVER_URL
stub_set open-prs.txt "5 main develop false"
GITHUB_REPOSITORY=acme/demo GITHUB_SERVER_URL=https://ghe.example.com run_bm
assert_bm_status pr-exists
grep -qx "pr=https://ghe.example.com/acme/demo/pull/5" "$GITHUB_OUTPUT" || fail "expected the GHES PR url: $(bm_log)"

# "Update branch" clicked on the PR: the carrier now holds develop too and is
# AHEAD of main. Nothing to push; no error, in a dry run or a real one.
clone_other
git switch -q backmerge/main
git merge -q --no-ff origin/develop -m "Merge develop into backmerge/main"
git push -q origin backmerge/main
UPDATED=$(git rev-parse HEAD)
cd "$TESTTMP/repo"
git fetch -q origin
stub_set open-prs.txt "42 backmerge/main develop false"
run_bm --dry-run
assert_bm_status pr-exists
run_bm
assert_bm_status pr-exists
[ "$(remote_sha backmerge/main)" = "$UPDATED" ] || fail "an ahead carrier must not be touched"

# main moves on: the carrier has diverged. Never rewritten; warn, keep the PR.
hotfix_on_main 1.0.2 h2.txt
GITHUB_ACTIONS=true run_bm
assert_bm_status pr-exists
grep -q "::warning" "$TESTTMP/bm.out" || fail "a diverged carrier must raise an Actions warning: $(bm_log)"
[ "$(remote_sha backmerge/main)" = "$UPDATED" ] || fail "a diverged carrier must not be rewritten"

# that PR was merged but its carrier kept: a new PR needs a fresh carrier, and
# both runs refuse instead of clobbering it
stub_set open-prs.txt ""
run_bm --dry-run
[ "$BM_EXIT" -eq 1 ] || fail "dry run must refuse a diverged leftover carrier, got $BM_EXIT: $(bm_log)"
run_bm
[ "$BM_EXIT" -eq 1 ] || fail "a diverged leftover carrier must exit 1, got $BM_EXIT: $(bm_log)"
grep -q "delete it" "$TESTTMP/bm.err" || fail "expected the delete hint: $(bm_log)"
[ "$(remote_sha backmerge/main)" = "$UPDATED" ] || fail "a leftover carrier must never be clobbered"
[ "$(pr_creates)" = 1 ] || fail "no PR may be opened from a refused carrier"
