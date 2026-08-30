#!/usr/bin/env bash
. "$(dirname "$0")/../../lib/harness.sh"

# The client-side pre-push hook runs the doctor's preflight set and blocks on
# criticals, with a GITDOCTOR_SKIP escape hatch.
mkrepo
cp "$SKILL_ROOT/integrations/hooks/pre-push" "$TESTTMP/repo/.git/hooks/pre-push"
chmod +x "$TESTTMP/repo/.git/hooks/pre-push"
export GITDOCTOR_PATH="$SKILL_ROOT/scripts/gitflow-doctor.sh"

# clean repo: pushes flow normally through the hook
commit_file a.txt "feat: fine"
git push -q origin main || fail "clean push must pass the preflight hook"

git switch -q develop
commit_file d.txt "feat: unreleased"
git push -q origin develop || fail "develop push must pass while repo is clean"

# a wrong-base hotfix exists -> preflight goes critical -> push blocked
git switch -qc hotfix/1.0.1 develop
commit_file f.txt "fix: urgent"
if git push -q -u origin hotfix/1.0.1 2>"$TESTTMP/push.err"; then
  fail "push should have been blocked by the pre-push preflight"
fi
grep -q "push blocked" "$TESTTMP/push.err" || fail "expected block message: $(cat "$TESTTMP/push.err")"

# deliberate one-time bypass
GITDOCTOR_SKIP=1 git push -q -u origin hotfix/1.0.1 || fail "GITDOCTOR_SKIP must bypass the hook"
