#!/usr/bin/env bash
. "$(dirname "$0")/../../lib/harness.sh"

# prefixes.* reach standalone runs (CI action, hooks) from .gitflow.json and
# come back as repo.prefixes. The release/backmerge BLOCKS share those key
# names with object values and must not be read as prefixes; flags still win.
mkrepo
assert_header() { # literal fragment
  grep -qF "$1" "$TESTTMP/out.jsonl" || fail "expected header fragment $1"
}

run_doctor --checks missing-back-merge
assert_header '"prefixes":{"feature":"feature/","release":"release/","hotfix":"hotfix/","backmerge":"backmerge/"}'

cat >.gitflow.json <<'EOF'
{
  "version": 1,
  "prefixes": { "feature": "feat/", "release": "rel/", "hotfix": "fix/", "backmerge": "sync/" },
  "release": { "maxConcurrent": 2 },
  "backmerge": { "strategy": "merge-tag" }
}
EOF
run_doctor --checks missing-back-merge
assert_header '"prefixes":{"feature":"feat/","release":"rel/","hotfix":"fix/","backmerge":"sync/"}'

# blocks before the prefixes on one line; an explicit flag beats the config
cat >.gitflow.json <<'EOF'
{ "version": 1, "release": { "maxConcurrent": 2 }, "backmerge": { "strategy": "merge-tag" }, "prefixes": { "release": "rel/" } }
EOF
run_doctor --checks missing-back-merge --release-prefix r/
assert_header '"prefixes":{"feature":"feature/","release":"r/","hotfix":"hotfix/","backmerge":"backmerge/"}'

# a configured prefix drives the checks, not just the header
git switch -qc rel/1.1.0 develop
run_doctor --checks branch-unrecognized
assert_no_finding branch-unrecognized
mv .gitflow.json gitflow.off
run_doctor --checks branch-unrecognized
assert_finding branch-unrecognized info
