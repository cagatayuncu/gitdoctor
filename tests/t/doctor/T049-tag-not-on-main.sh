#!/usr/bin/env bash
. "$(dirname "$0")/../../lib/harness.sh"

mkrepo
git switch -q develop
commit_file d.txt "feat: dev work"
git tag -a v9.9.9 -m "tagged off main"
git push -q origin develop v9.9.9
git switch -q main

run_doctor --checks tag-not-on-main
assert_finding tag-not-on-main warning
assert_data tag-not-on-main '"tag":"v9.9.9"'

# a tag on main is fine
git tag -a v1.0.0 -m ok
git push -q origin v1.0.0
run_doctor --checks tag-not-on-main
if grep '"id":"tag-not-on-main"' "$TESTTMP/out.jsonl" | grep -qF '"tag":"v1.0.0"'; then
  fail "v1.0.0 is on main and must not be flagged"
fi
