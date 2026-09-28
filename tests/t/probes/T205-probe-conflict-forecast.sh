#!/usr/bin/env bash
. "$(dirname "$0")/../../lib/harness.sh"

# The finish probe forecasts conflicts for the legs that are still pending,
# BEFORE any merge starts, and warns when a lower hotfix is still open.
mkrepo
printf 'line1\n<!-- comment -->\nline3\n' >web.config
git add web.config && git commit -qm "chore: web.config"
git tag -a v1.0.0 -m "Release 1.0.0"
git switch -q develop && git merge -q --ff-only main && git switch -q main
git push -q origin main develop v1.0.0

git switch -qc hotfix/1.0.1 main
printf 'line1\nline3\n' >web.config
git commit -qam "fix: drop the comment"
git switch -qc hotfix/1.0.2 main
printf 'line1\n<!-- comment --><rule/>\nline3\n' >web.config
git commit -qam "fix: add a rule"
git switch -qc hotfix/1.0.3 main
commit_file other.txt "fix: unrelated file"
git push -q origin hotfix/1.0.1 hotfix/1.0.2 hotfix/1.0.3
git switch -q main

# nothing finished yet: 1.0.3 is clean, but 1.0.1 and 1.0.2 are open below it
run_probe --probe finish-hotfix --branch hotfix/1.0.3 --version 1.0.3
grep -qF '"forecast":{"main":[],"backMerge":[]}' "$TESTTMP/probe.json" || fail "clean forecast expected"
assert_probe_warning "hotfix/1.0.1 is still open with a lower version"
assert_probe_warning "hotfix/1.0.2 is still open with a lower version"

# finish 1.0.1; now 1.0.2 would conflict on both legs
git merge -q --no-ff hotfix/1.0.1 -m "Release 1.0.1"
git tag -a v1.0.1 -m "Release 1.0.1"
git switch -q develop && git merge -q --no-ff v1.0.1 -m "Back-merge release 1.0.1"
git switch -q main
git push -q origin main develop v1.0.1
git push -q origin --delete hotfix/1.0.1 && git branch -qD hotfix/1.0.1

run_probe --probe finish-hotfix --branch hotfix/1.0.2 --version 1.0.2
assert_step merged-to-main false
grep -qF '"forecast":{"main":["web.config"],"backMerge":["web.config"]}' "$TESTTMP/probe.json" \
  || fail "web.config conflicts expected on both legs"
assert_probe_warning "conflicts predicted merging hotfix/1.0.2 into main: web.config"
# a shipped lower hotfix (tagged) no longer counts as open
if grep -qF "hotfix/1.0.1 is still open" "$TESTTMP/probe.json"; then fail "shipped 1.0.1 must not warn"; fi

# feature probes forecast the develop leg
git switch -qc feature/x develop
printf 'line1\nfeature\nline3\n' >web.config
git commit -qam "feat: x"
git switch -q develop
printf 'line1\ndevelop\nline3\n' >web.config
git commit -qam "feat: y"
git push -q origin develop
run_probe --probe finish-feature --branch feature/x
grep -qF '"forecast":{"develop":["web.config"]}' "$TESTTMP/probe.json" || fail "feature forecast expected"
