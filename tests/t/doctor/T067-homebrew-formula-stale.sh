#!/usr/bin/env bash
. "$(dirname "$0")/../../lib/harness.sh"

# With a Homebrew tap configured, the formula's url must ship the latest tag.
mkrepo
git tag -a v1.0.0 -m "1.0.0"
commit_file a.txt "feat: more"
git tag -a v1.1.0 -m "1.1.0"
git push -q origin main v1.0.0 v1.1.0
use_gh_stub

formula() { # tag -> a minimal formula body pointing at that tag
  printf 'class Demo < Formula\n  url "https://github.com/acme/demo/archive/refs/tags/%s.tar.gz"\n  sha256 "0000"\nend\n' "$1"
}

# not configured -> skipped, whatever gh says
run_doctor_gh --checks homebrew-formula-stale
assert_skipped homebrew-formula-stale not-configured

# configured but offline -> skipped with the gh state
run_doctor --checks homebrew-formula-stale --homebrew-tap acme/homebrew-tap --homebrew-formula Formula/demo.rb
assert_skipped homebrew-formula-stale offline

# tap unreadable (empty answer) -> skipped, never a false finding
run_doctor_gh --checks homebrew-formula-stale --homebrew-tap acme/homebrew-tap --homebrew-formula Formula/demo.rb
assert_skipped homebrew-formula-stale api-error

# formula ships the previous tag -> warning naming both versions, keyed by the latest tag
formula v1.0.0 >"$GH_STUB_DIR/tap-formula.txt"
run_doctor_gh --checks homebrew-formula-stale --homebrew-tap acme/homebrew-tap --homebrew-formula Formula/demo.rb
assert_finding homebrew-formula-stale warning
assert_data homebrew-formula-stale '"formula":"acme/homebrew-tap/Formula/demo.rb"'
assert_data homebrew-formula-stale '"formulaTag":"v1.0.0"'
assert_data homebrew-formula-stale '"latestTag":"v1.1.0"'
assert_data homebrew-formula-stale '"key":"v1.1.0"'
assert_data homebrew-formula-stale 'archive/refs/tags/v1.1.0.tar.gz | sha256sum'
assert_exit 1 "$DOCTOR_EXIT"

# formula at the latest tag -> clean
formula v1.1.0 >"$GH_STUB_DIR/tap-formula.txt"
run_doctor_gh --checks homebrew-formula-stale --homebrew-tap acme/homebrew-tap --homebrew-formula Formula/demo.rb
assert_no_finding homebrew-formula-stale
assert_exit 0 "$DOCTOR_EXIT"

# the same via .gitflow.json (standalone runs, no flags)
formula v1.0.0 >"$GH_STUB_DIR/tap-formula.txt"
cat >.gitflow.json <<'EOF'
{ "version": 1, "homebrew": { "tap": "acme/homebrew-tap", "formula": "Formula/demo.rb" } }
EOF
run_doctor_gh --checks homebrew-formula-stale
assert_finding homebrew-formula-stale warning
assert_data homebrew-formula-stale '"formulaTag":"v1.0.0"'

# tap without a formula path is not a configuration
cat >.gitflow.json <<'EOF'
{ "version": 1, "homebrew": { "tap": "acme/homebrew-tap" } }
EOF
run_doctor_gh --checks homebrew-formula-stale
assert_skipped homebrew-formula-stale not-configured
