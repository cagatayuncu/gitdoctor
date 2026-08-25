#!/usr/bin/env bash
. "$(dirname "$0")/../../lib/harness.sh"

mkrepo
git switch -qc release/v1.0 develop
git push -qu origin release/v1.0
git switch -qc hotfix/fix-thing main
git push -qu origin hotfix/fix-thing
git switch -qc release/2.0.0-rc.1 develop
git push -qu origin release/2.0.0-rc.1

run_doctor --checks branch-bad-version-name
assert_finding branch-bad-version-name warning
assert_data branch-bad-version-name '"branch":"release/v1.0"'
assert_data branch-bad-version-name '"branch":"hotfix/fix-thing"'
assert_data branch-bad-version-name '"branch":"release/2.0.0-rc.1"'

# --allow-prerelease accepts x.y.z-suffix but still rejects the others
run_doctor --checks branch-bad-version-name --allow-prerelease
assert_finding branch-bad-version-name warning
if grep '"id":"branch-bad-version-name"' "$TESTTMP/out.jsonl" | grep -qF '2.0.0-rc.1'; then
  fail "prerelease suffix must pass with --allow-prerelease"
fi
