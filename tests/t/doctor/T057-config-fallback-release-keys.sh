#!/usr/bin/env bash
. "$(dirname "$0")/../../lib/harness.sh"

# Standalone runs (hooks, CI action) read the changelog block, release.githubRelease
# and release.signedTags from .gitflow.json via the sed fallback — no flags needed.
mkrepo
git tag -a v1.0.0 -m "1.0.0"
git push -q origin v1.0.0

# no config: changelog + signed-tag checks are off
run_doctor --checks changelog-tag-mismatch,tag-unsigned
assert_skipped changelog-tag-mismatch not-configured
assert_skipped tag-unsigned not-configured

# changelog block without a file -> CHANGELOG.md (missing on main -> warning)
cat >.gitflow.json <<'EOF'
{
  "$schema": "https://raw.githubusercontent.com/cagatayuncu/gitdoctor/main/schema/gitflow.schema.json",
  "version": 1,
  "changelog": { "enabled": true },
  "release": { "githubRelease": false, "signedTags": true }
}
EOF
run_doctor --checks changelog-tag-mismatch,tag-unsigned
assert_finding changelog-tag-mismatch warning
assert_data changelog-tag-mismatch '"file":"CHANGELOG.md"'
assert_finding tag-unsigned warning # signedTags: true switched the check on
grep -q '"main":"main"' "$TESTTMP/out.jsonl" || fail "the \$schema URL (…/main/schema/…) must not be mistaken for branches.main"

# explicit file name is honoured; a heading for the tag clears the finding
printf '# Changelog\n\n## 1.0.0\n- first\n' >HISTORY.md
git add HISTORY.md && git commit -qm "docs: history" && git push -q origin main
cat >.gitflow.json <<'EOF'
{ "version": 1, "changelog": { "enabled": true, "file": "HISTORY.md" } }
EOF
run_doctor --checks changelog-tag-mismatch,tag-unsigned
assert_no_finding changelog-tag-mismatch
assert_skipped tag-unsigned not-configured # signedTags absent -> default off

# disabled changelog -> skipped even though the block names a file
cat >.gitflow.json <<'EOF'
{ "version": 1, "changelog": { "enabled": false, "file": "HISTORY.md" } }
EOF
run_doctor --checks changelog-tag-mismatch
assert_skipped changelog-tag-mismatch not-configured

# explicit flags win over the config
cat >.gitflow.json <<'EOF'
{ "version": 1, "changelog": { "enabled": true, "file": "HISTORY.md" } }
EOF
run_doctor --checks changelog-tag-mismatch --changelog CHANGELOG.md
assert_finding changelog-tag-mismatch warning
assert_data changelog-tag-mismatch '"file":"CHANGELOG.md"'

# backmerge.conflictPolicy.changelog is a different key: no changelog block -> still off
cat >.gitflow.json <<'EOF2'
{ "version": 1, "backmerge": { "conflictPolicy": { "changelog": "manual", "versionFiles": "higher" } } }
EOF2
run_doctor --checks changelog-tag-mismatch
assert_skipped changelog-tag-mismatch not-configured

# githubRelease: false reaches the gh check as not-configured
use_gh_stub
cat >.gitflow.json <<'EOF'
{ "version": 1, "release": { "githubRelease": false } }
EOF
run_doctor_gh --checks gh-release-missing-for-tag
assert_skipped gh-release-missing-for-tag not-configured
rm .gitflow.json
run_doctor_gh --checks gh-release-missing-for-tag
assert_finding gh-release-missing-for-tag info
