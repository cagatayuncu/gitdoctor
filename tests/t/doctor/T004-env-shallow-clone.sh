#!/usr/bin/env bash
. "$(dirname "$0")/../../lib/harness.sh"

mkrepo
commit "feat: more history"
git push -q origin main

git clone -q --depth 1 "file://$TESTTMP/origin.git" "$TESTTMP/shallow"
cd "$TESTTMP/shallow"
git branch -q develop origin/develop 2>/dev/null || git branch -q develop
run_doctor --checks env-shallow-clone,missing-back-merge
assert_finding env-shallow-clone warning
# ancestry-based findings must carry low confidence in a shallow clone
if grep '"id":"missing-back-merge"' "$TESTTMP/out.jsonl" | grep -q '"status":"fail"'; then
  assert_data missing-back-merge '"confidence":"low"'
fi
