#!/usr/bin/env bash
. "$(dirname "$0")/../../lib/harness.sh"

# A finish in flight records itself in .git/gitflow/finish.lock (branch,
# started, own=<sha> for every sha it put on origin). Any other update of
# origin/<main|develop|branch> since then is reported: a GUI push from this
# clone ("update by push") or a teammate's push picked up by a fetch.
mkrepo
root=$(git rev-parse main)
git switch -qc release/1.1.0 main
commit_file feature.txt "feat: the release content"
git push -q -u origin release/1.1.0
rel=$(git rev-parse release/1.1.0)

lock=$(git rev-parse --git-path gitflow/finish.lock)
mkdir -p "${lock%/*}"
printf 'branch=release/1.1.0\nstarted=0\nown=%s\nown=%s\n' "$root" "$rel" >"$lock"

# everything on origin so far was put there by this finish
run_doctor --checks external-push-detected
assert_no_finding external-push-detected

# the agent merges locally; a GUI client pushes that main before the agent does
git switch -q main && git merge -q --no-ff release/1.1.0 -m "Release 1.1.0"
merged=$(git rev-parse main)
git push -q origin main
run_doctor --checks external-push-detected
assert_finding external-push-detected info
assert_data external-push-detected '"branch":"release/1.1.0","since":0'
assert_data external-push-detected "{\"branch\":\"main\",\"sha\":\"$merged\""
assert_data external-push-detected '"via":"push"'

# a teammate pushes develop from another machine; our fetch picks it up
clone_other
git switch -q develop
commit_file teammate.txt "feat: teammate work"
git push -q origin develop
theirs=$(git rev-parse develop)
cd "$TESTTMP/repo"
run_doctor_online --checks external-push-detected
assert_data external-push-detected "{\"branch\":\"develop\",\"sha\":\"$theirs\""
assert_data external-push-detected '"via":"fetch"'

# the finish probe carries the same updates and warns
run_probe --probe finish-release --branch release/1.1.0 --version 1.1.0
assert_probe_warning 'origin changed 2 time(s) during this finish'
grep -qF "\"externalUpdates\":[" "$TESTTMP/probe.json" || fail "probe must emit externalUpdates"
grep -qF "\"sha\":\"$merged\"" "$TESTTMP/probe.json" || fail "externalUpdates must list the GUI push"

# a lock for another branch: two finishes at once
printf 'branch=release/9.9.9\nstarted=0\n' >"$lock"
run_probe --probe finish-release --branch release/1.1.0 --version 1.1.0
assert_probe_warning 'finish.lock says release/9.9.9 is being finished'
grep -qF '"externalUpdates":[]' "$TESTTMP/probe.json" || fail "another branch's lock must not attribute updates to this finish"

# once the finish records those shas as its own, nothing is external
printf 'branch=release/1.1.0\nstarted=0\nown=%s\nown=%s\nown=%s\nown=%s\n' "$root" "$rel" "$merged" "$theirs" >"$lock"
run_doctor --checks external-push-detected
assert_no_finding external-push-detected

# updates older than the finish do not count
printf 'branch=release/1.1.0\nstarted=%s\n' "$(( $(date +%s) + 3600 ))" >"$lock"
run_doctor --checks external-push-detected
assert_no_finding external-push-detected

# no finish in progress: nothing to compare against
rm -f "$lock"
run_doctor --checks external-push-detected
assert_no_finding external-push-detected
assert_exit 0 "$DOCTOR_EXIT"

# remote-tracking reflogs switched off: say so instead of reporting nothing
printf 'branch=release/1.1.0\nstarted=0\n' >"$lock"
git config core.logAllRefUpdates false
run_doctor --checks external-push-detected
assert_skipped external-push-detected reflog-disabled
run_probe --probe finish-release --branch release/1.1.0 --version 1.1.0
assert_probe_warning 'core.logAllRefUpdates is off'
