#!/usr/bin/env bash
. "$(dirname "$0")/../../lib/harness.sh"

# --list-checks / --explain work without a repository and validate ids; the
# same validation rejects typos in --checks / --skip.
cd "$TESTTMP" # not a git repo

bash "$DOCTOR" --list-checks >"$TESTTMP/ids.txt" || fail "--list-checks must exit 0"
n=$(grep -c . "$TESTTMP/ids.txt")
[ "$n" -eq 46 ] || fail "expected 46 check ids, got $n"
for id in missing-back-merge changelog-tag-mismatch tag-unsigned gh-protection-missing-develop gh-release-missing-for-tag back-merge-content-only orphaned-hotfix-branch; do
  grep -qx "$id" "$TESTTMP/ids.txt" || fail "id $id missing from --list-checks"
done
# every id has a recipe section, either its own or a shared one
while IFS= read -r id; do
  bash "$DOCTOR" --explain "$id" >"$TESTTMP/explain.txt" 2>&1 || fail "--explain $id failed: $(cat "$TESTTMP/explain.txt")"
  grep -q '^## ' "$TESTTMP/explain.txt" || fail "--explain $id printed no recipe heading"
done <"$TESTTMP/ids.txt"

bash "$DOCTOR" --explain missing-back-merge >"$TESTTMP/explain.txt" || fail "--explain must exit 0"
head -1 "$TESTTMP/explain.txt" | grep -qx '## missing-back-merge' || fail "recipe must start at its heading: $(head -1 "$TESTTMP/explain.txt")"
grep -q 'git merge --no-ff origin/main' "$TESTTMP/explain.txt" || fail "recipe body missing"
grep -q '^(online: https://github.com/cagatayuncu/gitdoctor/blob/main/references/fix-recipes.md#missing-back-merge)$' "$TESTTMP/explain.txt" || fail "online pointer missing"
if grep -q '^## untagged-merge-on-main' "$TESTTMP/explain.txt"; then fail "explain must stop at the next section"; fi

# ids that share a recipe resolve to the shared anchor
bash "$DOCTOR" --explain back-merge-content-only >"$TESTTMP/explain.txt"
head -1 "$TESTTMP/explain.txt" | grep -qx '## missing-back-merge' || fail "shared anchor for back-merge-content-only"
bash "$DOCTOR" --explain orphaned-hotfix-branch >"$TESTTMP/explain.txt"
head -1 "$TESTTMP/explain.txt" | grep -qx '## orphaned-release-branch' || fail "shared anchor for orphaned-hotfix-branch"

set +e
bash "$DOCTOR" --explain no-such-check >/dev/null 2>"$TESTTMP/err.txt"; c1=$?
bash "$DOCTOR" --checks missing-back-merge,typo-here --offline >/dev/null 2>"$TESTTMP/err2.txt"; c2=$?
bash "$DOCTOR" --skip typo-here --offline >/dev/null 2>"$TESTTMP/err3.txt"; c3=$?
set -e
assert_exit 4 "$c1"; grep -q "unknown check id 'no-such-check'" "$TESTTMP/err.txt" || fail "explain error text"
assert_exit 4 "$c2"; grep -q "\-\-checks: unknown check id 'typo-here'" "$TESTTMP/err2.txt" || fail "--checks validation text: $(cat "$TESTTMP/err2.txt")"
assert_exit 4 "$c3"; grep -q "\-\-skip: unknown check id 'typo-here'" "$TESTTMP/err3.txt" || fail "--skip validation text"
