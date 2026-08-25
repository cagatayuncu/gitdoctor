#!/usr/bin/env bash
. "$(dirname "$0")/../../lib/harness.sh"

mkrepo
git tag v1.0.0 # lightweight
git push -q origin v1.0.0

run_doctor --checks tag-lightweight-release
assert_finding tag-lightweight-release info
assert_data tag-lightweight-release '"tag":"v1.0.0"'

# annotated tags are fine
commit_file x.txt "feat: more"
git tag -a v1.0.1 -m annotated
git push -q origin main v1.0.1
run_doctor --checks tag-lightweight-release
assert_data tag-lightweight-release '"tag":"v1.0.0"' # still only the lightweight one
if grep '"id":"tag-lightweight-release"' "$TESTTMP/out.jsonl" | grep -qF '"tag":"v1.0.1"'; then
  fail "annotated v1.0.1 must not be flagged"
fi
