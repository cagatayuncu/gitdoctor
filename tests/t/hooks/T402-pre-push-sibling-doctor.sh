#!/usr/bin/env bash
. "$(dirname "$0")/../../lib/harness.sh"

# When the pre-push hook runs from a gitdoctor checkout (how the pre-commit
# framework invokes it via .pre-commit-hooks.yaml), it must find the doctor
# next to itself — no GITDOCTOR_PATH, no skill install, nothing on PATH.
mkrepo
unset GITDOCTOR_PATH
HOOK="$SKILL_ROOT/integrations/hooks/pre-push"

# HOME is $TESTTMP (no ~/.claude/skills), and PATH carries no gitflow-doctor.sh
if command -v gitflow-doctor.sh >/dev/null 2>&1; then fail "test precondition: gitflow-doctor.sh must not be on PATH"; fi

# pre-commit's `language: script` execs the file directly: the exec bit must be
# recorded in the index (a checkout on Linux/macOS inherits it from there)
if git -C "$SKILL_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git -C "$SKILL_ROOT" ls-files -s integrations/hooks/pre-push | grep -q '^100755 '     || fail "integrations/hooks/pre-push must be committed with mode 100755 (git update-index --chmod=+x)"
fi

# clean repo: hook passes and did NOT fall back to "doctor script not found"
bash "$HOOK" </dev/null >"$TESTTMP/hook.out" 2>"$TESTTMP/hook.err" || fail "clean repo must pass: $(cat "$TESTTMP/hook.err")"
if grep -q "doctor script not found" "$TESTTMP/hook.err"; then
  fail "hook did not resolve the sibling doctor: $(cat "$TESTTMP/hook.err")"
fi

# wrong-base hotfix -> the sibling doctor is really running: push blocked
git switch -q develop
commit_file d.txt "feat: unreleased"
git push -q origin develop
git switch -qc hotfix/1.0.1 develop
commit_file f.txt "fix: urgent"
set +e
bash "$HOOK" </dev/null >"$TESTTMP/hook.out" 2>"$TESTTMP/hook.err"
code=$?
set -e
[ "$code" -eq 1 ] || fail "expected the hook to block (exit 1), got $code: $(cat "$TESTTMP/hook.err")"
grep -q "push blocked" "$TESTTMP/hook.err" || fail "expected block message: $(cat "$TESTTMP/hook.err")"
grep -q "wrong-base-hotfix\|develop-only" "$TESTTMP/hook.err" || fail "expected the finding title in the block message: $(cat "$TESTTMP/hook.err")"
