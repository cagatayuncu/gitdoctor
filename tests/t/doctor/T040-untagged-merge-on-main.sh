#!/usr/bin/env bash
. "$(dirname "$0")/../../lib/harness.sh"

mkrepo
git switch -qc release/1.0.0 develop
commit_file rel.txt "chore: prep"
git switch -q main
git merge -q --no-ff release/1.0.0 -m "Release 1.0.0 (forgot the tag)"
git push -q origin main
git branch -qD release/1.0.0

run_doctor --checks untagged-merge-on-main
assert_finding untagged-merge-on-main warning

# recipe: tag the merge commit, push the tag
MSHA=$(git rev-parse main)
git tag -a v1.0.0 "$MSHA" -m "Release 1.0.0"
git push -q origin v1.0.0
run_doctor --checks untagged-merge-on-main
assert_no_finding untagged-merge-on-main
