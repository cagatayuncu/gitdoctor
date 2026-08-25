# shellcheck shell=bash
# shellcheck disable=SC2034 # DOCTOR_EXIT/PROBE_EXIT are consumed by the sourcing test files
# Test harness: full environment isolation + fixture repo builders.
# Sourced by every test file. Requires TESTTMP and SKILL_ROOT (set by run-tests.sh).
set -eu

: "${TESTTMP:?TESTTMP must be set by run-tests.sh}"
: "${SKILL_ROOT:?SKILL_ROOT must be set by run-tests.sh}"

export HOME="$TESTTMP"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_DATE="2024-01-01T00:00:00Z" GIT_COMMITTER_DATE="2024-01-01T00:00:00Z"
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=t@t.test
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=t@t.test
export GIT_TERMINAL_PROMPT=0
unset GH_TOKEN GITHUB_TOKEN GH_HOST 2>/dev/null || true

DOCTOR="$SKILL_ROOT/scripts/gitflow-doctor.sh"
NOW=1704067200 # 2024-01-01T00:00:00Z, matches the fixed commit dates

# shellcheck source=tests/lib/assert.sh
. "$(dirname "${BASH_SOURCE[0]}")/assert.sh"

# --- repo builders ----------------------------------------------------------
COMMIT_N=0

# One commit appending to f.txt (deterministic content, conflicts on purpose
# when both sides of a merge use it).
commit() {
  COMMIT_N=$((COMMIT_N + 1))
  echo "$COMMIT_N $1" >>f.txt
  git add f.txt
  git commit -qm "$1"
}

# One commit to a caller-chosen file (for non-conflicting parallel history).
commit_file() { # file message
  echo "x $2" >>"$1"
  git add "$1"
  git commit -qm "$2"
}

# Work repo + bare fake origin; main and develop exist locally and on origin.
# Leaves you inside $TESTTMP/repo on main.
mkrepo() {
  git init -q --bare -b main "$TESTTMP/origin.git"
  git init -q -b main "$TESTTMP/repo"
  cd "$TESTTMP/repo"
  git remote add origin "$TESTTMP/origin.git"
  commit "chore: root"
  git branch develop
  git push -q origin main develop
}

# A second clone acting as "another machine" pushing to the same origin.
# Leaves you inside $TESTTMP/other.
clone_other() {
  git clone -q "$TESTTMP/origin.git" "$TESTTMP/other"
  cd "$TESTTMP/other"
}

# --- doctor invocation ------------------------------------------------------
DOCTOR_EXIT=0
PROBE_EXIT=0

run_doctor() { # extra doctor args; offline mode (fake origin is local anyway)
  set +e
  bash "$DOCTOR" --format jsonl --offline --now "$NOW" "$@" >"$TESTTMP/out.jsonl" 2>"$TESTTMP/doctor.err"
  DOCTOR_EXIT=$?
  set -e
}

run_doctor_online() { # with fetch + ls-remote against the local fake origin
  set +e
  bash "$DOCTOR" --format jsonl --now "$NOW" "$@" >"$TESTTMP/out.jsonl" 2>"$TESTTMP/doctor.err"
  DOCTOR_EXIT=$?
  set -e
}

run_probe() { # --probe ... --branch ... [--version ...]
  set +e
  bash "$DOCTOR" --offline --now "$NOW" "$@" >"$TESTTMP/probe.json" 2>"$TESTTMP/doctor.err"
  PROBE_EXIT=$?
  set -e
}

# --- gh stub ----------------------------------------------------------------
use_gh_stub() {
  export GH_STUB_DIR="$TESTTMP/gh"
  mkdir -p "$GH_STUB_DIR"
  cp "$SKILL_ROOT/tests/fixtures/gh/"*.txt "$GH_STUB_DIR/"
  chmod +x "$SKILL_ROOT/tests/stubs/gh" 2>/dev/null || true
  export PATH="$SKILL_ROOT/tests/stubs:$PATH"
}

stub_set() { # fixture-file content...
  printf '%s\n' "${@:2}" >"$GH_STUB_DIR/$1"
}

run_doctor_gh() { # gh-enabled run: no --offline (would disable gh), fetch skipped
  set +e
  bash "$DOCTOR" --format jsonl --no-fetch --now "$NOW" --assume-github acme/demo "$@" \
    >"$TESTTMP/out.jsonl" 2>"$TESTTMP/doctor.err"
  DOCTOR_EXIT=$?
  set -e
}

run_probe_gh() {
  set +e
  bash "$DOCTOR" --no-fetch --now "$NOW" --assume-github acme/demo "$@" \
    >"$TESTTMP/probe.json" 2>"$TESTTMP/doctor.err"
  PROBE_EXIT=$?
  set -e
}
