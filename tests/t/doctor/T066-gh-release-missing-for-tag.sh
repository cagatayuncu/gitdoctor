#!/usr/bin/env bash
. "$(dirname "$0")/../../lib/harness.sh"

# Every semver tag reachable from main should have a GitHub Release
# (release.githubRelease defaults to true).
mkrepo
use_gh_stub

# no semver tag yet -> skipped
run_doctor_gh --checks gh-release-missing-for-tag
assert_skipped gh-release-missing-for-tag no-semver-tags

git tag -a v1.0.0 -m "1.0.0"
commit_file a.txt "feat: more"
git tag -a v1.1.0 -m "1.1.0"
git tag legacy-build-7 # non-semver: never considered
git push -q origin main v1.0.0 v1.1.0 legacy-build-7

# stub: no releases at all -> both tags reported, one finding each, keyed by tag
run_doctor_gh --checks gh-release-missing-for-tag
assert_finding gh-release-missing-for-tag info
assert_data gh-release-missing-for-tag '"tag":"v1.0.0"'
grep '"id":"gh-release-missing-for-tag"' "$TESTTMP/out.jsonl" | grep -qF '"tag":"v1.1.0"' || fail "v1.1.0 must be reported too"
grep '"id":"gh-release-missing-for-tag"' "$TESTTMP/out.jsonl" | grep -qF '"key":"v1.1.0"' || fail "finding must carry key=v1.1.0"
if grep '"id":"gh-release-missing-for-tag"' "$TESTTMP/out.jsonl" | grep -qF 'legacy-build-7'; then
  fail "non-semver tag must not be considered"
fi
grep '"id":"gh-release-missing-for-tag"' "$TESTTMP/out.jsonl" | grep -qF 'gh release create v1.0.0 --verify-tag' || fail "expected gh release create hint"

# one release exists -> only the other tag remains
stub_set release-list.txt v1.0.0
run_doctor_gh --checks gh-release-missing-for-tag
assert_data gh-release-missing-for-tag '"tag":"v1.1.0"'
if grep '"id":"gh-release-missing-for-tag"' "$TESTTMP/out.jsonl" | grep -qF '"tag":"v1.0.0"'; then
  fail "v1.0.0 has a release and must not be reported"
fi

# all released -> clean
stub_set release-list.txt v1.0.0 v1.1.0
run_doctor_gh --checks gh-release-missing-for-tag
assert_no_finding gh-release-missing-for-tag

# repo does not publish GitHub Releases -> skipped, not a finding
stub_set release-list.txt ""
run_doctor_gh --checks gh-release-missing-for-tag --no-github-release
assert_skipped gh-release-missing-for-tag not-configured

# no gh -> skipped
run_doctor --checks gh-release-missing-for-tag
assert_skipped gh-release-missing-for-tag offline
