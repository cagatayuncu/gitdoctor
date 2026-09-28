#!/usr/bin/env bash
. "$(dirname "$0")/../../lib/harness.sh"

# The 2.0.0-hotfix.12 scenario: two hotfixes cut from the same main; the first
# one finishes and deletes a comment the second one edits. The second branch
# is now behind main and its finish would conflict on BOTH legs.
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
git push -q origin hotfix/1.0.2 hotfix/1.0.3

# finish hotfix/1.0.1 by hand (main + tag + develop), branch deleted
git switch -q main && git merge -q --no-ff hotfix/1.0.1 -m "Release 1.0.1"
git tag -a v1.0.1 -m "Release 1.0.1"
git switch -q develop && git merge -q --no-ff v1.0.1 -m "Back-merge release 1.0.1"
git switch -q main && git branch -qD hotfix/1.0.1
git push -q origin main develop v1.0.1

run_doctor --checks flow-branch-behind-main
assert_finding flow-branch-behind-main warning
grep -F '"branch":"hotfix/1.0.2"' "$TESTTMP/out.jsonl" | grep -F '"behind":2' \
  | grep -qF '"conflicts":{"main":["web.config"],"develop":["web.config"]}' \
  || fail "hotfix/1.0.2 must be 2 behind with web.config conflicts on both legs"
# behind but clean -> info, empty conflict lists
grep -F '"branch":"hotfix/1.0.3"' "$TESTTMP/out.jsonl" | grep -F '"severity":"info"' \
  | grep -qF '"conflicts":{"main":[],"develop":[]}' \
  || fail "hotfix/1.0.3 must be an info finding with no conflicts"
assert_exit 1 "$DOCTOR_EXIT"

# several open hotfixes: listed in version order with base, lag and conflicts
run_doctor --checks multiple-hotfix-branches
assert_finding multiple-hotfix-branches info
assert_data multiple-hotfix-branches '"branches":[{"branch":"hotfix/1.0.2","version":"1.0.2","base":"v1.0.0","behind":2,"mainConflicts":["web.config"]},{"branch":"hotfix/1.0.3","version":"1.0.3","base":"v1.0.0","behind":2,"mainConflicts":[]}]'
assert_data multiple-hotfix-branches '"finishFirst":"hotfix/1.0.2"'

# once the stale branch merges main in and resolves on its own branch, it is clean
git switch -q hotfix/1.0.3 && git merge -q --no-ff origin/main -m "Merge main into hotfix/1.0.3"
git push -q origin hotfix/1.0.3
git push -q origin --delete hotfix/1.0.2 && git switch -q main && git branch -qD hotfix/1.0.2
run_doctor --checks flow-branch-behind-main,multiple-hotfix-branches
assert_no_finding flow-branch-behind-main
assert_no_finding multiple-hotfix-branches
