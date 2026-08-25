#!/usr/bin/env bash
# Test runner: executes every tests/t/**/*.sh in a fresh temp dir.
# Tests are independent, so they run in parallel batches (process spawns are
# expensive on Windows; JOBS-way parallelism divides the wall-clock cost).
# Usage: bash tests/run-tests.sh [t/doctor/T030-missing-back-merge.sh ...]
#        JOBS=4 bash tests/run-tests.sh
set -u

cd "$(dirname "$0")" || exit 1
ROOT=$(pwd)
SKILL_ROOT=${SKILL_ROOT:-$(cd "$ROOT/.." && pwd)}
export SKILL_ROOT
JOBS=${JOBS:-8}

if [ $# -gt 0 ]; then
  tests=$(printf '%s\n' "$@")
else
  # shellcheck disable=SC2012 # deliberate: ls over find (test names are ASCII; avoids Windows find.exe ambiguity)
  tests=$(ls t/doctor/*.sh t/probes/*.sh t/dryrun/*.sh 2>/dev/null | sort)
fi

RESULTS=$(mktemp -d)

run_one() { # index test-file
  local i=$1 tf=$2 tmp
  tmp=$(mktemp -d)
  if (cd "$tmp" && TESTTMP=$tmp bash "$ROOT/$tf" >"$tmp/test.log" 2>&1); then
    printf 'ok %s - %s\n' "$i" "$tf" >"$RESULTS/$i"
  else
    {
      printf 'not ok %s - %s\n' "$i" "$tf"
      sed 's/^/#   /' "$tmp/test.log"
    } >"$RESULTS/$i"
  fi
  rm -rf "$tmp" 2>/dev/null || true
}

i=0
batch=0
for tf in $tests; do
  i=$((i + 1))
  printf '%s' "$tf" >"$RESULTS/$i.name"
  run_one "$i" "$tf" &
  batch=$((batch + 1))
  if [ "$batch" -ge "$JOBS" ]; then
    wait
    batch=0
  fi
done
wait

pass=0
failn=0
n=1
while [ "$n" -le "$i" ]; do
  f="$RESULTS/$n"
  if [ -e "$f" ]; then
    first=""
    IFS= read -r first <"$f" || true
    case "$first" in
      "ok "*) pass=$((pass + 1)) ;;
      *) failn=$((failn + 1)) ;;
    esac
    cat "$f"
  else
    # a crashed/killed parallel job never wrote its result — that is a failure,
    # not a silent omission
    failn=$((failn + 1))
    tname=""
    [ -e "$RESULTS/$n.name" ] && IFS= read -r tname <"$RESULTS/$n.name"
    printf 'not ok %s - %s\n#   MISSING RESULT (job crashed?)\n' "$n" "${tname:-unknown}"
  fi
  n=$((n + 1))
done
echo "# $pass passed, $failn failed, $i total"
rm -rf "$RESULTS" 2>/dev/null || true
[ "$failn" -eq 0 ]
