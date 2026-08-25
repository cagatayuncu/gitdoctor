#!/usr/bin/env bash
. "$(dirname "$0")/../../lib/harness.sh"

mkrepo
git tag -a release-candidate -m rc
git tag -a v1.0 -m "not full semver"
git tag -a v1.0.0 -m good
git push -q origin release-candidate v1.0 v1.0.0

run_doctor --checks non-semver-tag
assert_finding non-semver-tag info
assert_data non-semver-tag '"tag":"release-candidate"'
assert_data non-semver-tag '"tag":"v1.0"'
if grep '"id":"non-semver-tag"' "$TESTTMP/out.jsonl" | grep -qF '"tag":"v1.0.0"'; then
  fail "v1.0.0 is valid semver and must not be flagged"
fi

# ignoreTags globs suppress specific tags
run_doctor --checks non-semver-tag --ignore-tags 'release-*,v1.0'
assert_no_finding non-semver-tag
