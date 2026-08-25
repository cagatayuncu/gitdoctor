#!/usr/bin/env bash
. "$(dirname "$0")/../../lib/harness.sh"

mkrepo
git tag -a v1.0.0 -m prefixed
git tag 1.0.0
git push -q origin v1.0.0 1.0.0

run_doctor --checks tag-prefix-collision
assert_finding tag-prefix-collision warning
assert_data tag-prefix-collision '"tags":["v1.0.0","1.0.0"]'

# recipe: delete the unprefixed twin
git tag -d 1.0.0 >/dev/null
git push -q origin :refs/tags/1.0.0
run_doctor --checks tag-prefix-collision
assert_no_finding tag-prefix-collision
