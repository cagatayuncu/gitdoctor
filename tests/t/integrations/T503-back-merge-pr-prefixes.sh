#!/usr/bin/env bash
. "$(dirname "$0")/../../lib/harness.sh"

# Custom prefixes from .gitflow.json drive back-merge-pr.sh end to end (via
# the doctor's repo.prefixes): the release gate looks at rel/*, the carrier
# is sync/<main>.
mkrepo
use_gh_stub
cat >.gitflow.json <<'EOF'
{ "version": 1, "prefixes": { "release": "rel/", "backmerge": "sync/" } }
EOF

git switch -qc hotfix/1.0.1 main
commit_file h.txt "fix: crash"
git switch -q main
git merge -q --no-ff hotfix/1.0.1 -m "Hotfix 1.0.1"
git push -q origin main

# rel/1.1.0 took the hotfix back-merge -> it carries main's commits
git switch -qc rel/1.1.0 develop
git merge -q --no-ff main -m "Back-merge hotfix 1.0.1"
git push -q origin rel/1.1.0
git switch -q main
run_bm
assert_bm_status skipped-release-open

# release gone: the PR is opened from the configured carrier
git push -q origin --delete rel/1.1.0
git branch -qD rel/1.1.0
run_bm
assert_bm_status pr-opened
[ "$(remote_sha sync/main)" = "$(git rev-parse main)" ] || fail "carrier must be sync/main: $(bm_log)"
grep -qF -- "--head sync/main" "$GH_STUB_DIR/pr-create.log" || fail "PR head must be sync/main: $(cat "$GH_STUB_DIR/pr-create.log")"
