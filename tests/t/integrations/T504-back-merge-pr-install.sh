#!/usr/bin/env bash
. "$(dirname "$0")/../../lib/harness.sh"

# back-merge-pr.sh finds the doctor in every layout it ships in: a gitdoctor
# checkout (the Action, the Claude Code plugin), the skill install
# (install.sh: both files in scripts/), Homebrew (both in bin/ as gitdoctor +
# gitdoctor-back-merge-pr) and PATH. A dry run proves the doctor really ran.
unset GITDOCTOR_PATH
mkrepo
use_gh_stub
git switch -qc hotfix/1.0.1 main
commit_file h.txt "fix: crash"
git switch -q main
git merge -q --no-ff hotfix/1.0.1 -m "Hotfix 1.0.1"
git push -q origin main

run_script() { # path-to-back-merge-pr [PATH prefix]
  export GITHUB_OUTPUT="$TESTTMP/gh-output"
  : >"$GITHUB_OUTPUT"
  set +e
  PATH="${2:-}${2:+:}$PATH" bash "$1" --dry-run >"$TESTTMP/bm.out" 2>"$TESTTMP/bm.err"
  BM_EXIT=$?
  set -e
}

# --help: usage on stdout, exit 0 (Homebrew's formula test calls it)
bash "$SKILL_ROOT/integrations/github-actions/back-merge-pr.sh" --help >"$TESTTMP/help.out" || fail "--help must exit 0"
grep -q "usage: back-merge-pr" "$TESTTMP/help.out" || fail "--help must print usage: $(cat "$TESTTMP/help.out")"

# skill install: install.sh puts it next to the doctor
bash "$SKILL_ROOT/install.sh" >/dev/null
SKILL_SCRIPTS="$HOME/.claude/skills/gitdoctor/scripts"
[ -f "$SKILL_SCRIPTS/back-merge-pr.sh" ] || fail "install.sh must ship back-merge-pr.sh into the skill's scripts/"
run_script "$SKILL_SCRIPTS/back-merge-pr.sh"
assert_bm_status would-open

# Homebrew layout: bin/gitdoctor + bin/gitdoctor-back-merge-pr
mkdir -p "$TESTTMP/brew/bin"
cp "$DOCTOR" "$TESTTMP/brew/bin/gitdoctor"
cp "$SKILL_ROOT/integrations/github-actions/back-merge-pr.sh" "$TESTTMP/brew/bin/gitdoctor-back-merge-pr"
run_script "$TESTTMP/brew/bin/gitdoctor-back-merge-pr"
assert_bm_status would-open

# alone in a directory, doctor on PATH as gitdoctor
mkdir -p "$TESTTMP/lone" "$TESTTMP/onpath"
cp "$SKILL_ROOT/integrations/github-actions/back-merge-pr.sh" "$TESTTMP/lone/back-merge-pr.sh"
cp "$DOCTOR" "$TESTTMP/onpath/gitdoctor"
chmod +x "$TESTTMP/onpath/gitdoctor"
run_script "$TESTTMP/lone/back-merge-pr.sh" "$TESTTMP/onpath"
assert_bm_status would-open

# nowhere to be found: a clear error, never a silent pass
if command -v gitdoctor >/dev/null 2>&1 || command -v gitflow-doctor.sh >/dev/null 2>&1; then
  fail "test precondition: no doctor may be on PATH"
fi
run_script "$TESTTMP/lone/back-merge-pr.sh"
[ "$BM_EXIT" -eq 1 ] || fail "expected exit 1 without a doctor, got $BM_EXIT: $(bm_log)"
grep -q "not found" "$TESTTMP/bm.err" || fail "expected a not-found error: $(bm_log)"
