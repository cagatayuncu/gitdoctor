#!/usr/bin/env bash
. "$(dirname "$0")/../../lib/harness.sh"

# The server-side pre-receive hook must reject a wrong-base hotfix at push
# time and let a correct one through. File-path remotes run receive-pack
# locally, so the hook executes for real in this fixture.
mkrepo
cp "$SKILL_ROOT/integrations/hooks/pre-receive" "$TESTTMP/origin.git/hooks/pre-receive"
chmod +x "$TESTTMP/origin.git/hooks/pre-receive"

git switch -q develop
commit_file d.txt "feat: unreleased"
git push -q origin develop

# hotfix cut from develop -> rejected with the wrong-base message
git switch -qc hotfix/1.0.1 develop
commit_file f.txt "fix: urgent"
if git push -q -u origin hotfix/1.0.1 2>"$TESTTMP/push.err"; then
  fail "wrong-base hotfix push should have been rejected"
fi
grep -q "wrong-base-hotfix" "$TESTTMP/push.err" || fail "expected wrong-base-hotfix in rejection: $(cat "$TESTTMP/push.err")"

# bad branch name -> rejected
git switch -qc hotfix/oops main
commit_file g.txt "fix: name"
if git push -q -u origin hotfix/oops 2>"$TESTTMP/push2.err"; then
  fail "badly named hotfix push should have been rejected"
fi
grep -q "hotfix/X.Y.Z" "$TESTTMP/push2.err" || fail "expected naming message: $(cat "$TESTTMP/push2.err")"

# correct hotfix from main -> accepted
git switch -qc hotfix/1.0.2 main
commit_file h.txt "fix: proper"
git push -q -u origin hotfix/1.0.2 || fail "correct hotfix push must pass the gate"

# escape hatch: GITDOCTOR_SKIP bypasses (local transport inherits the env)
git switch -q develop
GITDOCTOR_SKIP=1 git push -q -u origin hotfix/1.0.1 || fail "GITDOCTOR_SKIP push must bypass the gate"
