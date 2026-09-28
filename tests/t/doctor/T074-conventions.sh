#!/usr/bin/env bash
. "$(dirname "$0")/../../lib/harness.sh"

# --conventions infers the house style from the last finishes on main so
# `init` can propose messages/tag settings instead of imposing gitdoctor's.
conv() { # literal fragment expected in the conventions JSON
  grep -qF "$1" "$TESTTMP/conv.json" || { cat "$TESTTMP/conv.json" >&2; fail "expected conventions fragment $1"; }
}
run_conv() {
  bash "$DOCTOR" --offline --conventions "$@" >"$TESTTMP/conv.json" 2>"$TESTTMP/doctor.err" || fail "--conventions must exit 0"
}

# --- team style: bare tags, suffix-counter hotfixes, git's default messages,
# the BRANCH merged into develop -------------------------------------------
mkrepo
git tag -a 2.0.0 -m 2.0.0
git push -q origin 2.0.0
team_hotfix() { # version
  git switch -qc "hotfix/$1" main
  commit_file "fix-$1.txt" "fix: $1"
  git switch -q main
  git merge -q --no-ff "hotfix/$1" -m "Merge branch 'hotfix/$1'"
  git tag -a "$1" -m "$1"
  git switch -q develop
  git merge -q --no-ff "hotfix/$1" -m "Merge branch 'hotfix/$1' into develop"
  git switch -q main
  git branch -qD "hotfix/$1"
}
team_hotfix 2.0.0-hotfix.1
team_hotfix 2.0.0-hotfix.2
team_hotfix 2.0.0-hotfix.3
git push -q origin main develop --tags

run_conv
conv '"sampled":4'
conv '"tagPrefix":""'
conv '"tagType":"annotated"'
conv '"mergeToMain":"Merge branch '"'"'{branch}'"'"'"'
conv '"backMerge":"Merge branch '"'"'{branch}'"'"' into {develop}"'
conv '"tag":"{tag}"'
conv '"backmergeStrategy":"merge-branch"'
conv '"versionScheme":{"scheme":"suffix-counter","hotfixPattern":"{base}-hotfix.{n}"}'

# --- gitdoctor's own defaults: v-prefix, "Release X.Y.Z", tag merged back ---
cd "$TESTTMP" && rm -rf repo origin.git
mkrepo
gd_release() { # version
  git switch -qc "release/$1" develop
  commit_file "rel-$1.txt" "chore(release): $1"
  git switch -q main
  git merge -q --no-ff "release/$1" -m "Release $1"
  git tag -a "v$1" -m "Release $1"
  git switch -q develop
  git merge -q --no-ff "v$1" -m "Back-merge release $1"
  git branch -qD "release/$1"
}
gd_release 1.0.0
gd_release 1.1.0
git push -q origin main develop --tags

run_conv
conv '"sampled":2'
conv '"tagPrefix":"v"'
conv '"mergeToMain":"Release {version}"'
conv '"backMerge":"Back-merge release {version}"'
conv '"tag":"Release {version}"'
conv '"backmergeStrategy":"merge-tag"'
conv '"versionScheme":{"scheme":"semver"}'

# --- no tags yet: nothing to infer, still valid JSON -------------------------
cd "$TESTTMP" && rm -rf repo origin.git
mkrepo
run_conv
conv '"sampled":0'
conv '"messages":{}'
