#!/usr/bin/env bash
. "$(dirname "$0")/../../lib/harness.sh"

# --format sarif: SARIF 2.1.0 for code-scanning uploads. One rule per failing
# check id, one result per finding, severity mapped to error/warning/note,
# a stable fingerprint from id:key, skipped checks omitted.
mkrepo
git branch junk-a && git push -q origin junk-a
git switch -q develop
commit_file d.txt "feat: unreleased"
git push -q origin develop
git switch -qc hotfix/1.0.1 develop
commit_file f.txt "fix: urgent"
git push -qu origin hotfix/1.0.1

set +e
bash "$DOCTOR" --format sarif --offline --now "$NOW" --checks wrong-base-hotfix,branch-unrecognized,tag-unsigned \
  >"$TESTTMP/out.sarif" 2>"$TESTTMP/doctor.err"
code=$?
set -e
assert_exit 2 "$code"

S=$TESTTMP/out.sarif
grep -qF '"$schema":"https://json.schemastore.org/sarif-2.1.0.json","version":"2.1.0"' "$S" || fail "sarif envelope"
grep -qF '"driver":{"name":"gitdoctor","version":"' "$S" || fail "tool driver"
grep -qF '{"id":"wrong-base-hotfix","name":"wrong-base-hotfix","shortDescription":{"text":"wrong-base-hotfix"},"helpUri":"https://github.com/cagatayuncu/gitdoctor/blob/main/references/fix-recipes.md#wrong-base-hotfix","defaultConfiguration":{"level":"error"}}' "$S" || fail "rule for wrong-base-hotfix"
grep -qF '"defaultConfiguration":{"level":"note"}' "$S" || fail "info -> note level"
grep -qF '"ruleId":"wrong-base-hotfix","level":"error","message":{"text":"hotfix/1.0.1 contains 1 develop-only commit(s)' "$S" || fail "result for wrong-base-hotfix"
grep -qF '\n\nFix:\ngit switch -c hotfix/1.0.1-rebased origin/main\ngit cherry-pick <fix commits>' "$S" || fail "fix commands embedded in message"
grep -qF '"artifactLocation":{"uri":".gitflow.json","uriBaseId":"%SRCROOT%"}' "$S" || fail "location anchor"
grep -qF '"partialFingerprints":{"gitdoctorKey":"wrong-base-hotfix:hotfix/1.0.1"}' "$S" || fail "fingerprint"
grep -qF '"partialFingerprints":{"gitdoctorKey":"branch-unrecognized:junk-a"}' "$S" || fail "fingerprint for junk-a"
if grep -qF 'tag-unsigned' "$S"; then fail "skipped checks must not appear in SARIF"; fi
[ "$(grep -o '"ruleId"' "$S" | wc -l)" -eq 2 ] || fail "expected exactly 2 results"

# well-formed JSON when a parser is around (CI runners have python3)
if python3 -c "import json" >/dev/null 2>&1; then # a real python3, not the Windows Store alias
  python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); r=d["runs"][0]; assert len(r["results"])==2 and len(r["tool"]["driver"]["rules"])==2' "$S" \
    || fail "SARIF is not valid JSON or has unexpected shape"
fi

# clean scan -> empty rules/results, exit 0
git switch -q develop
git push -q origin --delete hotfix/1.0.1 junk-a
git branch -qD hotfix/1.0.1; git branch -qD junk-a
bash "$DOCTOR" --format sarif --offline --now "$NOW" --checks wrong-base-hotfix,branch-unrecognized >"$TESTTMP/clean.sarif" || fail "clean sarif run must exit 0"
grep -qF '"rules":[]' "$TESTTMP/clean.sarif" || fail "empty rules"
grep -qF '"results":[]' "$TESTTMP/clean.sarif" || fail "empty results"
