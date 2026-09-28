#!/usr/bin/env bash
. "$(dirname "$0")/../../lib/harness.sh"

# --workspace: one read-only pass over several repos released in lockstep —
# per-repo doctor summary, per-repo finish probe for a shared branch, and
# cross-repo tag consistency (tag-convention-drift).
ws() { # literal fragment expected in the workspace JSON
  grep -qF "$1" "$TESTTMP/ws.json" || { cat "$TESTTMP/ws.json" >&2; cat "$TESTTMP/doctor.err" >&2; fail "expected workspace fragment $1"; }
}
run_ws() {
  set +e
  bash "$DOCTOR" --offline --now "$NOW" --workspace "$TESTTMP/.gitflow-workspace.json" "$@" >"$TESTTMP/ws.json" 2>"$TESTTMP/doctor.err"
  WS_EXIT=$?
  set -e
}
mkrepo_at() { # name
  git init -q --bare -b main "$TESTTMP/$1-origin.git"
  git init -q -b main "$TESTTMP/$1"
  (
    cd "$TESTTMP/$1"
    git remote add origin "$TESTTMP/$1-origin.git"
    printf '{ "tagPrefix": "" }\n' >.gitflow.json
    git add .gitflow.json && git commit -qm "chore: root"
    git branch develop
    git push -q origin main develop
  )
}

mkrepo_at backend
mkrepo_at ui
mkrepo_at survey
( cd "$TESTTMP/backend" && git tag -a 1.0.0 -m 1.0.0 && git push -q origin 1.0.0 )
( cd "$TESTTMP/ui" && git tag -a 1.0.0 -m 1.0.0 && git push -q origin 1.0.0 )
( cd "$TESTTMP/survey" && git tag 1.0.0 && git push -q origin 1.0.0 ) # lightweight: the 1.9.11 accident

cat >"$TESTTMP/.gitflow-workspace.json" <<'EOF'
{
  "repos": [
    "./backend",
    "./ui",
    { "path": "./survey" },
    { "path": "./sdk", "optional": true }
  ],
  "pushPolicy": "all-verified"
}
EOF

run_ws --tag 1.0.0
ws '"pushPolicy":"all-verified"'
ws '{"path":"./backend","optional":false,"status":"ok"'
ws '{"path":"./sdk","optional":true,"status":"missing"}'
ws '"tag":{"name":"1.0.0","type":"annotated","message":"{tag}","onMainTip":true}'
ws '"tag":{"name":"1.0.0","type":"lightweight","message":"","onMainTip":true}'
ws '"id":"tag-convention-drift","severity":"warning"'
ws '"reasons":["type"]'
ws '"ready":false'
assert_exit 1 "$WS_EXIT"

# fix the survey tag -> consistent, ready
( cd "$TESTTMP/survey" && git tag -d 1.0.0 >/dev/null && git tag -a 1.0.0 -m 1.0.0 && git push -q -f origin 1.0.0 )
run_ws --tag 1.0.0
if grep -qF tag-convention-drift "$TESTTMP/ws.json"; then fail "no drift expected"; fi
ws '"ready":true'
assert_exit 0 "$WS_EXIT"

# a tag missing in one required repo, and one not on main's tip
( cd "$TESTTMP/backend" && git commit -q --allow-empty -m "fix: later" && git push -q origin main && git tag -a 1.0.1 -m 1.0.1 HEAD~1 && git push -q origin 1.0.1 )
( cd "$TESTTMP/ui" && git tag -a 1.0.1 -m 1.0.1 && git push -q origin 1.0.1 )
run_ws --tag 1.0.1
ws '"reasons":["missing","not-on-main-tip"]'

# a shared hotfix branch: probed where it exists, skipped where it does not
( cd "$TESTTMP/backend" && git switch -qc hotfix/1.0.2 && git commit -q --allow-empty -m "fix: x" && git push -q origin hotfix/1.0.2 )
run_ws --branch hotfix/1.0.2
ws '"branch":{"name":"hotfix/1.0.2","present":true},"probe":{"gitflowDoctor"'
ws '"probe":"finish-hotfix","branch":"hotfix/1.0.2","version":"1.0.2"'
ws '"branch":{"name":"hotfix/1.0.2","present":false,"skipped":"no branch"}'

# a required repo that is missing is critical
rm -rf "$TESTTMP/ui"
run_ws
ws '"id":"workspace-repo-missing","severity":"critical"'
assert_exit 2 "$WS_EXIT"
