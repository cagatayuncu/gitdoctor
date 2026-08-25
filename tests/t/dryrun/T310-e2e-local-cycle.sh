#!/usr/bin/env bash
. "$(dirname "$0")/../../lib/harness.sh"

# End-to-end local-mode cycle exactly as the agent would drive it:
# feature finish -> release 1.0.0 finish (version file, atomic tag push,
# tag back-merge) -> hotfix 1.0.1 finish -> final doctor must be fully green.
PAT='"version"[[:space:]]*:[[:space:]]*"([^"]+)"'
VF=(--version-file package.json --version-pattern "$PAT")

mkrepo
git switch -q develop
printf '{\n  "name": "demo",\n  "version": "0.0.0"\n}\n' >package.json
git add package.json
git commit -qm "chore: add package.json"
git push -q origin develop

# --- feature ---
git switch -qc feature/login develop
commit_file login.txt "feat: login"
git push -qu origin feature/login
git switch -q develop
git merge -q --no-ff feature/login -m "Merge feature/login into develop"
git push -q origin develop
git push -q origin --delete feature/login
git branch -qd feature/login

# --- release 1.0.0 ---
git switch -qc release/1.0.0 develop
printf '{\n  "name": "demo",\n  "version": "1.0.0"\n}\n' >package.json
git commit -qam "chore(release): 1.0.0"
git push -qu origin release/1.0.0
git switch -q main
git merge -q --ff-only origin/main
git merge -q --no-ff release/1.0.0 -m "Release 1.0.0"
git tag -a v1.0.0 -m "Release 1.0.0"
git push -q --atomic origin main refs/tags/v1.0.0
git switch -q develop
git merge -q --no-ff v1.0.0 -m "Back-merge release 1.0.0"
git push -q origin develop
git push -q origin --delete release/1.0.0
git branch -qd release/1.0.0

run_probe --probe finish-release --branch release/1.0.0 --version 1.0.0 "${VF[@]}"
assert_step version-bumped true
assert_step merged-to-main true
# branch refs are gone, so the tag-ancestry fallback (not branch-gone) must be
# the evidence — distinguishes the two fallback tiers
assert_step_data merged-to-main '"via":"tag"'
assert_step tag-exists true
assert_step tag-pushed true
assert_step back-merged true
assert_step remote-branch-deleted true
assert_step local-branch-deleted true

# --- hotfix 1.0.1 ---
git switch -qc hotfix/1.0.1 main
commit_file hot.txt "fix: production bug"
printf '{\n  "name": "demo",\n  "version": "1.0.1"\n}\n' >package.json
git commit -qam "chore(release): 1.0.1"
git push -qu origin hotfix/1.0.1
git switch -q main
git merge -q --no-ff hotfix/1.0.1 -m "Hotfix 1.0.1"
git tag -a v1.0.1 -m "Hotfix 1.0.1"
git push -q --atomic origin main refs/tags/v1.0.1
git switch -q develop
git merge -q --no-ff v1.0.1 -m "Back-merge hotfix 1.0.1"
git push -q origin develop
git push -q origin --delete hotfix/1.0.1
git branch -qd hotfix/1.0.1

# --- the repo must now be healthy: zero findings at warning+ severity ---
# (info-level notes like env-origin-not-github are expected on a local origin)
run_doctor_online --min-severity warning "${VF[@]}"
assert_exit 0 "$DOCTOR_EXIT"
if grep -q '"status":"fail"' "$TESTTMP/out.jsonl"; then
  fail "expected a fully green doctor after the cycle"
fi
