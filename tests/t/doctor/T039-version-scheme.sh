#!/usr/bin/env bash
. "$(dirname "$0")/../../lib/harness.sh"

# Version ordering is computed by the doctor itself (strict SemVer, plus the
# suffix-counter scheme), so git's versionsort.suffix can never change which
# tag counts as the latest one.
assert_versions() { # literal fragment of repo.versions on the summary line
  grep -F '"gitflowDoctor"' "$TESTTMP/out.jsonl" | grep -qF "$1" || fail "expected repo.versions fragment $1"
}

mkrepo
for t in 2.0.0 2.0.0-hotfix.9 2.0.0-hotfix.10 2.0.0-hotfix.12; do git tag -a "$t" -m "$t"; done
git push -q origin --tags

run_sc() { run_doctor --tag-prefix "" --version-scheme suffix-counter "$@"; }
run_sc --checks non-semver-tag
assert_versions '"versions":{"scheme":"suffix-counter","latestTag":"2.0.0-hotfix.12","nextHotfix":"2.0.0-hotfix.13"}'

# a hostile versionsort.suffix must not move the latest tag
git config versionsort.suffix -
run_sc --checks non-semver-tag
assert_versions '"latestTag":"2.0.0-hotfix.12"'
git config --unset versionsort.suffix

# open hotfix branches reserve their numbers: the suggestion goes past them
git switch -qc hotfix/2.0.0-hotfix.13 main
git switch -qc hotfix/2.0.0-hotfix.15 main
git switch -q main
run_sc --checks branch-bad-version-name,release-version-collision
assert_versions '"nextHotfix":"2.0.0-hotfix.16"'
assert_no_finding branch-bad-version-name # counter names are valid under the scheme
assert_no_finding release-version-collision

# ...but not under plain semver without --allow-prerelease
run_doctor --tag-prefix "" --checks branch-bad-version-name
assert_finding branch-bad-version-name warning
git branch -qD hotfix/2.0.0-hotfix.13 hotfix/2.0.0-hotfix.15

# a hotfix numbered below the latest tag collides (hotfixes are guarded too)
git switch -qc hotfix/2.0.0-hotfix.11 main
git switch -q main
run_sc --checks release-version-collision
assert_finding release-version-collision warning
assert_data release-version-collision '"branch":"hotfix/2.0.0-hotfix.11"'
assert_data release-version-collision '"latestTag":"2.0.0-hotfix.12"'
git branch -qD hotfix/2.0.0-hotfix.11

# bad scheme input is a usage error
set +e
bash "$DOCTOR" --offline --version-scheme calver >/dev/null 2>&1; c1=$?
bash "$DOCTOR" --offline --version-scheme suffix-counter --hotfix-pattern '{base}.{n}' >/dev/null 2>&1; c2=$?
set -e
assert_exit 4 "$c1"
assert_exit 4 "$c2"

# --- strict SemVer (default scheme) ------------------------------------------
cd "$TESTTMP" && rm -rf repo origin.git
mkrepo
git tag -a v2.0.0-rc.1 -m rc1
git tag -a v2.0.0-rc.10 -m rc10
git tag -a v2.0.0-rc.2 -m rc2
git push -q origin --tags
run_doctor --checks non-semver-tag
assert_versions '"versions":{"scheme":"semver","latestTag":"v2.0.0-rc.10","nextHotfix":""}'
# regression: release/2.0.0 outranks its own prereleases — the old
# suffix-stripping comparison called this a collision with v2.0.0-rc.10
git switch -qc release/2.0.0 develop
git switch -q main
run_doctor --checks release-version-collision
assert_no_finding release-version-collision
git branch -qD release/2.0.0

git tag -a v2.0.0 -m final
git push -q origin v2.0.0
run_doctor --checks non-semver-tag
assert_versions '"latestTag":"v2.0.0"' # a release outranks its prereleases

# the config fallback reads the scheme keys too
printf '{ "tagPrefix": "", "versionScheme": { "scheme": "suffix-counter", "hotfixPattern": "{base}-fix.{n}" } }\n' >.gitflow.json
git tag -a 3.0.0-fix.4 -m fix4
run_doctor --checks non-semver-tag
assert_versions '"versions":{"scheme":"suffix-counter","latestTag":"3.0.0-fix.4","nextHotfix":"3.0.0-fix.5"}'
