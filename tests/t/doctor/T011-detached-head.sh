#!/usr/bin/env bash
. "$(dirname "$0")/../../lib/harness.sh"

mkrepo
git switch -q --detach main
run_doctor --checks detached-head
assert_finding detached-head warning

git switch -q main
run_doctor --checks detached-head
assert_no_finding detached-head
