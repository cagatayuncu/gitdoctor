#!/usr/bin/env bash
. "$(dirname "$0")/../../lib/harness.sh"

mkrepo
git switch -qc feature/old develop
echo x >old.txt
git add old.txt
GIT_COMMITTER_DATE="2020-01-01T00:00:00Z" GIT_AUTHOR_DATE="2020-01-01T00:00:00Z" \
  git commit -qm "feat: ancient work"
git push -qu origin feature/old
git switch -q develop

run_doctor --checks branch-stale-inactive,branch-stale-merged
assert_finding branch-stale-inactive info
assert_data branch-stale-inactive '"branch":"feature/old"'
assert_data branch-stale-inactive '"inactiveDays":1461'
assert_no_finding branch-stale-merged

# a generous stale window silences it
run_doctor --checks branch-stale-inactive --stale-days 2000
assert_no_finding branch-stale-inactive
