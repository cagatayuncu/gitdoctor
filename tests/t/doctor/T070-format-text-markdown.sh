#!/usr/bin/env bash
. "$(dirname "$0")/../../lib/harness.sh"

# Human-facing renderers: --format text and --format markdown carry the same
# findings, fix commands and recipe pointers as the JSON contract, and keep the
# exit-code semantics.
mkrepo
git switch -q develop
commit_file d.txt "feat: unreleased"
git push -q origin develop
git switch -qc hotfix/1.0.1 develop # wrong base -> critical
commit_file f.txt "fix: urgent"
git push -qu origin hotfix/1.0.1

set +e
bash "$DOCTOR" --format text --offline --now "$NOW" --checks wrong-base-hotfix,tag-unsigned >"$TESTTMP/out.txt" 2>"$TESTTMP/doctor.err"
code=$?
set -e
assert_exit 2 "$code"
grep -q '^gitdoctor [0-9]' "$TESTTMP/out.txt" || fail "text header missing"
grep -q '^CRIT  wrong-base-hotfix  hotfix/1.0.1 contains 1 develop-only commit' "$TESTTMP/out.txt" || fail "text finding line missing: $(cat "$TESTTMP/out.txt")"
grep -q 'fix: git switch -c hotfix/1.0.1-rebased origin/main' "$TESTTMP/out.txt" || fail "first fix command missing"
grep -q '^           git cherry-pick <fix commits>' "$TESTTMP/out.txt" || fail "continuation fix command missing"
grep -q 'recipe: references/fix-recipes.md#wrong-base-hotfix' "$TESTTMP/out.txt" || fail "recipe pointer missing"
grep -q '^SKIP  tag-unsigned  (not-configured)' "$TESTTMP/out.txt" || fail "skipped line missing"
grep -q '^1 critical, 0 warning, 0 info, 0 ok, 1 skipped$' "$TESTTMP/out.txt" || fail "summary line missing: $(cat "$TESTTMP/out.txt")"
if grep -q '"id":' "$TESTTMP/out.txt"; then fail "text output must not contain JSON"; fi

set +e
bash "$DOCTOR" --format markdown --offline --now "$NOW" --checks wrong-base-hotfix,tag-unsigned >"$TESTTMP/out.md" 2>"$TESTTMP/doctor.err"
code=$?
set -e
assert_exit 2 "$code"
grep -q '^## :red_circle: gitdoctor: 1 critical finding(s)$' "$TESTTMP/out.md" || fail "markdown heading missing"
grep -q '^`1 critical · 0 warning · 0 info · 0 ok · 1 skipped`$' "$TESTTMP/out.md" || fail "markdown summary missing"
grep -q '^| :red_circle: | `wrong-base-hotfix` | hotfix/1.0.1 contains' "$TESTTMP/out.md" || fail "markdown table row missing"
grep -q '^<details><summary>Fix commands</summary>$' "$TESTTMP/out.md" || fail "details block missing"
grep -q '^\*\*wrong-base-hotfix\*\* (\[recipe\](https://github.com/cagatayuncu/gitdoctor/blob/main/references/fix-recipes.md#wrong-base-hotfix))$' "$TESTTMP/out.md" || fail "recipe link missing"
grep -q '^git cherry-pick <fix commits>$' "$TESTTMP/out.md" || fail "fix command in code block missing"

# clean scan renders the green header / "no findings"
git switch -q develop
git push -q origin --delete hotfix/1.0.1
git branch -qD hotfix/1.0.1
bash "$DOCTOR" --format markdown --offline --now "$NOW" --checks wrong-base-hotfix >"$TESTTMP/clean.md" || fail "clean markdown run must exit 0"
grep -q '^## :green_circle: gitdoctor: clean$' "$TESTTMP/clean.md" || fail "green header missing"
bash "$DOCTOR" --format text --offline --now "$NOW" --checks wrong-base-hotfix >"$TESTTMP/clean.txt" || fail "clean text run must exit 0"
grep -q '^no findings$' "$TESTTMP/clean.txt" || fail "'no findings' missing"

# unknown format is a usage error
set +e
bash "$DOCTOR" --format yaml --offline >/dev/null 2>&1
code=$?
set -e
assert_exit 4 "$code"
