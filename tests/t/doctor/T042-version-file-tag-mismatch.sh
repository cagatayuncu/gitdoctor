#!/usr/bin/env bash
. "$(dirname "$0")/../../lib/harness.sh"

PAT='"version"[[:space:]]*:[[:space:]]*"([^"]+)"'

mkrepo
printf '{\n  "name": "demo",\n  "version": "1.0.0"\n}\n' >package.json
git add package.json
git commit -qm "chore: add package.json"
git tag -a v1.1.0 -m "1.1.0"
git push -q origin main v1.1.0

run_doctor --checks version-file-tag-mismatch --version-file package.json --version-pattern "$PAT"
assert_finding version-file-tag-mismatch warning
assert_data version-file-tag-mismatch '"fileVersion":"1.0.0"'
assert_data version-file-tag-mismatch '"tagVersion":"1.1.0"'

# align the file on main
printf '{\n  "name": "demo",\n  "version": "1.1.0"\n}\n' >package.json
git commit -qam "chore: bump version file"
git push -q origin main
run_doctor --checks version-file-tag-mismatch --version-file package.json --version-pattern "$PAT"
assert_no_finding version-file-tag-mismatch

# without configuration the check reports skipped
run_doctor --checks version-file-tag-mismatch
assert_skipped version-file-tag-mismatch not-configured

# a version file WITHOUT a trailing newline must still be read
# (capture/capture_all last-line regression)
printf '2.0.0' >VERSION
git add VERSION
git commit -qm "chore: add VERSION file"
git push -q origin main
run_doctor --checks version-file-tag-mismatch --version-file VERSION --version-pattern '^([0-9A-Za-z.+-]+)$'
assert_finding version-file-tag-mismatch warning
assert_data version-file-tag-mismatch '"fileVersion":"2.0.0"'
