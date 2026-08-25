#!/usr/bin/env bash
. "$(dirname "$0")/../../lib/harness.sh"

mkrepo
git tag -a v1.0.0 -m original
git push -q origin v1.0.0

# someone retags locally onto a different commit
git tag -d v1.0.0 >/dev/null
commit_file x.txt "feat: more"
git push -q origin main
git tag -a v1.0.0 -m retagged

run_doctor --checks tag-sha-mismatch,tag-unpushed
assert_finding tag-sha-mismatch critical
assert_data tag-sha-mismatch '"tag":"v1.0.0"'
assert_exit 2 "$DOCTOR_EXIT"
