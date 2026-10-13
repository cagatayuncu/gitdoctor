#!/usr/bin/env bash
. "$(dirname "$0")/../../lib/harness.sh"

# integrations/github-actions/back-merge-pr.sh: a conflict-free missing
# back-merge gets ONE pull request backmerge/main -> develop; re-runs refresh
# that PR instead of opening another.
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

# 1. aligned repo: nothing to do
run_bm
assert_bm_status not-needed
[ "$(pr_creates)" = 0 ] || fail "no PR expected on an aligned repo"

# 2. hotfix merged to main, never back-merged; --dry-run touches nothing
hotfix_on_main 1.0.1 h1.txt
MAIN_SHA=$(git rev-parse main)
run_bm --dry-run
assert_bm_status would-open
[ -z "$(remote_sha backmerge/main)" ] || fail "--dry-run must not push the carrier"
[ "$(pr_creates)" = 0 ] || fail "--dry-run must not open a PR"

# 3. PR creation refused (repo setting off): explicit error with the fix
export GH_STUB_FAIL=pr-create
run_bm
unset GH_STUB_FAIL
[ "$BM_EXIT" -eq 1 ] || fail "expected exit 1 when gh pr create fails, got $BM_EXIT: $(bm_log)"
grep -q "create and approve pull requests" "$TESTTMP/bm.err" || fail "expected the repo-setting hint: $(bm_log)"

# 4. real run: carrier pushed at main's tip, PR opened against develop
run_bm
assert_bm_status pr-opened
[ "$(remote_sha backmerge/main)" = "$MAIN_SHA" ] || fail "carrier must point at main's tip: $(bm_log)"
grep -qF -- "--base develop --head backmerge/main" "$GH_STUB_DIR/pr-create.log" || fail "wrong PR refs: $(cat "$GH_STUB_DIR/pr-create.log")"
grep -qx "pr=https://github.com/acme/demo/pull/42" "$GITHUB_OUTPUT" || fail "expected the PR url output: $(bm_log)"
grep -q "Create a merge commit" "$GH_STUB_DIR/pr-body.txt" || fail "PR body must ask for a merge commit"
grep -q "fix: 1.0.1" "$GH_STUB_DIR/pr-body.txt" || fail "PR body must list the missing commits"

# 5. re-run with that PR open: no second PR
stub_set open-prs.txt "42 backmerge/main develop"
run_bm
assert_bm_status pr-exists
[ "$(pr_creates)" = 1 ] || fail "a re-run must not open a second PR"

# 6. another hotfix lands on main: the open PR's carrier fast-forwards
hotfix_on_main 1.0.2 h2.txt
run_bm
assert_bm_status pr-updated
[ "$(remote_sha backmerge/main)" = "$(git rev-parse main)" ] || fail "carrier must follow main: $(bm_log)"
[ "$(pr_creates)" = 1 ] || fail "an update must not open a second PR"
