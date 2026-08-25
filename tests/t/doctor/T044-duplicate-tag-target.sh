#!/usr/bin/env bash
. "$(dirname "$0")/../../lib/harness.sh"

mkrepo
git tag -a v1.0.0 -m a
git tag -a v1.0.1 -m b # same commit as v1.0.0
git push -q origin v1.0.0 v1.0.1

run_doctor --checks duplicate-tag-target
assert_finding duplicate-tag-target warning
assert_data duplicate-tag-target '"tags":["v1.0.0","v1.0.1"]'

# distinct targets are fine
git tag -d v1.0.1 >/dev/null
git push -q origin :refs/tags/v1.0.1
commit_file x.txt "feat: more"
git tag -a v1.0.1 -m b2
git push -q origin main v1.0.1
run_doctor --checks duplicate-tag-target
assert_no_finding duplicate-tag-target
