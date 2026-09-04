#!/usr/bin/env bash
. "$(dirname "$0")/../../lib/harness.sh"

# Opt-in check: with --require-signed-tags every semver tag must be an
# annotated tag object carrying a GPG/SSH signature.
mkrepo
git tag -a v1.0.0 -m "annotated, unsigned"
commit_file a.txt "feat: more"
git tag v1.0.1 # lightweight: cannot carry a signature at all
git push -q origin main v1.0.0 v1.0.1

# off by default
run_doctor --checks tag-unsigned
assert_skipped tag-unsigned not-configured

run_doctor --checks tag-unsigned --require-signed-tags
assert_finding tag-unsigned warning
assert_data tag-unsigned '"tag":"v1.0.0"'
grep '"id":"tag-unsigned"' "$TESTTMP/out.jsonl" | grep -qF '"tag":"v1.0.1"' || fail "lightweight v1.0.1 must be flagged as unsigned"
assert_exit 1 "$DOCTOR_EXIT"

# a tag object with a signature block is accepted (mktag does not verify the
# signature, which is exactly what we need to fake one without a keyring)
commit_file b.txt "feat: signed release"
head=$(git rev-parse HEAD)
tagsha=$(printf 'object %s\ntype commit\ntag v1.0.2\ntagger test <t@t.test> 1704067200 +0000\n\nRelease 1.0.2\n-----BEGIN PGP SIGNATURE-----\n\niQEzBAABCAAdFiEEfake\n-----END PGP SIGNATURE-----\n' "$head" | git mktag)
git update-ref refs/tags/v1.0.2 "$tagsha"
git push -q origin main v1.0.2

run_doctor --checks tag-unsigned --require-signed-tags
assert_finding tag-unsigned warning # v1.0.0 and v1.0.1 still unsigned
if grep '"id":"tag-unsigned"' "$TESTTMP/out.jsonl" | grep -qF '"tag":"v1.0.2"'; then
  fail "signed v1.0.2 must not be flagged"
fi

# ignoreTags globs apply; with every unsigned tag ignored the check is clean
run_doctor --checks tag-unsigned --require-signed-tags --ignore-tags 'v1.0.0,v1.0.1'
assert_no_finding tag-unsigned
assert_exit 0 "$DOCTOR_EXIT"
