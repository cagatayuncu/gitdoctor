#!/usr/bin/env bash
. "$(dirname "$0")/../../lib/harness.sh"

# Findings carry a key (the branch/tag/sha/file they are about); --ignore-findings
# accepts "id:key" for fine-grained suppression, and --format baseline emits the
# entries that would silence the current scan (merging what is already ignored).
mkrepo
git branch junk-a && git branch junk-b
git push -q origin junk-a junk-b
git switch -q develop
commit_file d.txt "feat: unreleased"
git push -q origin develop
git switch -qc hotfix/1.0.1 develop # wrong base -> critical, keyed by branch
commit_file f.txt "fix: urgent"
git push -qu origin hotfix/1.0.1

run_doctor --checks branch-unrecognized,wrong-base-hotfix
assert_finding branch-unrecognized info
assert_data branch-unrecognized '"key":"junk-a"'
grep '"id":"branch-unrecognized"' "$TESTTMP/out.jsonl" | grep -qF '"key":"junk-b"' || fail "junk-b finding must carry its key"
assert_data wrong-base-hotfix '"key":"hotfix/1.0.1"'
assert_exit 2 "$DOCTOR_EXIT"

# id:key suppresses exactly one instance
run_doctor --checks branch-unrecognized --ignore-findings branch-unrecognized:junk-a
assert_skipped branch-unrecognized config-ignored
grep '"id":"branch-unrecognized"' "$TESTTMP/out.jsonl" | grep '"status":"fail"' | grep -qF '"key":"junk-b"' || fail "junk-b must still be reported"
if grep '"id":"branch-unrecognized"' "$TESTTMP/out.jsonl" | grep '"status":"fail"' | grep -qF '"key":"junk-a"'; then
  fail "junk-a must be suppressed"
fi

# baseline: union of already-ignored entries + every current failing finding; exit 0 despite the critical
set +e
bash "$DOCTOR" --format baseline --offline --now "$NOW" --checks branch-unrecognized,wrong-base-hotfix \
  --ignore-findings branch-unrecognized:junk-a >"$TESTTMP/baseline.json" 2>"$TESTTMP/doctor.err"
code=$?
set -e
assert_exit 0 "$code"
expected='{"doctor":{"ignoreFindings":["branch-unrecognized:junk-a","wrong-base-hotfix:hotfix/1.0.1","branch-unrecognized:junk-b"]}}' # already-ignored first, then findings in check order
[ "$(cat "$TESTTMP/baseline.json")" = "$expected" ] || fail "baseline mismatch: $(cat "$TESTTMP/baseline.json")"

# feeding the baseline back silences the scan entirely
run_doctor --checks branch-unrecognized,wrong-base-hotfix \
  --ignore-findings 'branch-unrecognized:junk-a,branch-unrecognized:junk-b,wrong-base-hotfix:hotfix/1.0.1'
assert_no_finding branch-unrecognized
assert_no_finding wrong-base-hotfix
assert_exit 0 "$DOCTOR_EXIT"

# ...until something NEW appears
git branch junk-c && git push -q origin junk-c
run_doctor --checks branch-unrecognized \
  --ignore-findings 'branch-unrecognized:junk-a,branch-unrecognized:junk-b'
assert_finding branch-unrecognized info
assert_data branch-unrecognized '"key":"junk-c"'

# whole-check suppression still works as before
run_doctor --checks branch-unrecognized --ignore-findings branch-unrecognized
assert_no_finding branch-unrecognized
