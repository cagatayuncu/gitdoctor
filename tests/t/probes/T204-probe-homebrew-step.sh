#!/usr/bin/env bash
. "$(dirname "$0")/../../lib/harness.sh"

# The release/hotfix finish probe grows a homebrew-formula step only when a tap
# is configured; done = the formula url already ships the version's tag.
mkrepo
git switch -qc release/1.0.0 develop
commit_file rel.txt "chore: prep 1.0.0"
git push -qu origin release/1.0.0
git switch -q main
git merge -q --no-ff release/1.0.0 -m "Release 1.0.0"
git tag -a v1.0.0 -m "1.0.0"
git push -q origin main v1.0.0
use_gh_stub

formula() { printf 'class Demo < Formula\n  url "https://github.com/acme/demo/archive/refs/tags/%s.tar.gz"\n  sha256 "0000"\nend\n' "$1"; }
HB=(--homebrew-tap acme/homebrew-tap --homebrew-formula Formula/demo.rb)

# unconfigured: no such step at all
run_probe_gh --probe finish-release --branch release/1.0.0 --version 1.0.0
if grep -q '"step":"homebrew-formula"' "$TESTTMP/probe.json"; then fail "step must be absent without a tap"; fi

# configured, tap unreadable -> pending with a reason
run_probe_gh --probe finish-release --branch release/1.0.0 --version 1.0.0 "${HB[@]}"
assert_step homebrew-formula false
assert_step_data homebrew-formula 'could not read the formula'

# formula still on the previous version -> pending, names what it ships
formula v0.9.0 >"$GH_STUB_DIR/tap-formula.txt"
run_probe_gh --probe finish-release --branch release/1.0.0 --version 1.0.0 "${HB[@]}"
assert_step homebrew-formula false
assert_step_data homebrew-formula '"formula":"acme/homebrew-tap/Formula/demo.rb"'
assert_step_data homebrew-formula '"shipped":"v0.9.0"'
assert_step_data homebrew-formula 'does not point at v1.0.0'
assert_step merged-to-main true # the rest of the walk is unaffected

# bumped -> done
formula v1.0.0 >"$GH_STUB_DIR/tap-formula.txt"
run_probe_gh --probe finish-release --branch release/1.0.0 --version 1.0.0 "${HB[@]}"
assert_step homebrew-formula true

# hotfix probes carry the step too
git switch -qc hotfix/1.0.1 main
commit_file fix.txt "fix: urgent"
git push -qu origin hotfix/1.0.1
run_probe_gh --probe finish-hotfix --branch hotfix/1.0.1 --version 1.0.1 "${HB[@]}"
assert_step homebrew-formula false
assert_step_data homebrew-formula 'does not point at v1.0.1'

# feature probes never do
run_probe_gh --probe finish-feature --branch hotfix/1.0.1 "${HB[@]}"
if grep -q '"step":"homebrew-formula"' "$TESTTMP/probe.json"; then fail "feature probe must not carry the step"; fi

# no gh -> pending with the gh state, still no crash
run_probe --probe finish-release --branch release/1.0.0 --version 1.0.0 "${HB[@]}"
assert_step homebrew-formula false
assert_step_data homebrew-formula 'gh unavailable (offline)'
