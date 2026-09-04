#!/usr/bin/env bash
. "$(dirname "$0")/../../lib/harness.sh"

# The latest release tag must have a heading in the changelog on main.
mkrepo

# not configured -> skipped
run_doctor --checks changelog-tag-mismatch
assert_skipped changelog-tag-mismatch not-configured

# configured but no semver tag yet -> skipped
run_doctor --checks changelog-tag-mismatch --changelog CHANGELOG.md
assert_skipped changelog-tag-mismatch no-semver-tags

# tag exists, changelog file missing on main -> warning (file missing)
git tag -a v1.0.0 -m "1.0.0"
git push -q origin v1.0.0
run_doctor --checks changelog-tag-mismatch --changelog CHANGELOG.md
assert_finding changelog-tag-mismatch warning
assert_data changelog-tag-mismatch '"tag":"v1.0.0"'
assert_data changelog-tag-mismatch 'file missing on main'
assert_data changelog-tag-mismatch '"key":"v1.0.0"'
assert_exit 1 "$DOCTOR_EXIT"

# changelog present but only older sections; "11.0.0" must not count as 1.0.0
printf '# Changelog\n\n## 11.0.0 (2030-01-01)\n- nope\n\n## 0.9.0 (2023-12-01)\n- old\n' >CHANGELOG.md
git add CHANGELOG.md && git commit -qm "docs: changelog" && git push -q origin main
run_doctor --checks changelog-tag-mismatch --changelog CHANGELOG.md
assert_finding changelog-tag-mismatch warning
assert_data changelog-tag-mismatch 'no heading mentions 1.0.0'

# keep-a-changelog style heading clears it
printf '# Changelog\n\n## [1.0.0] - 2024-01-01\n- first\n\n## 0.9.0 (2023-12-01)\n- old\n' >CHANGELOG.md
git add CHANGELOG.md && git commit -qm "docs: 1.0.0" && git push -q origin main
run_doctor --checks changelog-tag-mismatch --changelog CHANGELOG.md
assert_no_finding changelog-tag-mismatch
assert_exit 0 "$DOCTOR_EXIT"

# prefixed heading style (## v1.0.1) clears it too, and only the LATEST tag matters
commit_file x.txt "fix: patch"
git tag -a v1.0.1 -m "1.0.1"
printf '# Changelog\n\n## v1.0.1\n- patch\n\n## [1.0.0] - 2024-01-01\n- first\n' >CHANGELOG.md
git add CHANGELOG.md && git commit -qm "docs: 1.0.1" && git push -q origin main v1.0.1
run_doctor --checks changelog-tag-mismatch --changelog CHANGELOG.md
assert_no_finding changelog-tag-mismatch

# the version mentioned only in body text (not a heading) does not count
commit_file y.txt "fix: another"
git tag -a v1.0.2 -m "1.0.2"
printf '# Changelog\n\nSee 1.0.2 notes below.\n\n## v1.0.1\n- patch\n' >CHANGELOG.md
git add CHANGELOG.md && git commit -qm "docs: body only" && git push -q origin main v1.0.2
run_doctor --checks changelog-tag-mismatch --changelog CHANGELOG.md
assert_finding changelog-tag-mismatch warning
assert_data changelog-tag-mismatch '"tag":"v1.0.2"'
