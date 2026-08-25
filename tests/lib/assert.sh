# shellcheck shell=bash
# Assertions over the doctor's jsonl output ($TESTTMP/out.jsonl) and probe
# output ($TESTTMP/probe.json). No jq: the emitter's key order is fixed, so
# plain grep on contiguous fragments is reliable.

fail() {
  echo "ASSERT FAIL: $*" >&2
  if [ -f "$TESTTMP/out.jsonl" ]; then
    echo "--- doctor output ---" >&2
    sed 's/^/  /' "$TESTTMP/out.jsonl" >&2
  fi
  if [ -f "$TESTTMP/probe.json" ]; then
    echo "--- probe output ---" >&2
    sed 's/^/  /' "$TESTTMP/probe.json" >&2
  fi
  if [ -s "$TESTTMP/doctor.err" ]; then
    echo "--- doctor stderr ---" >&2
    sed 's/^/  /' "$TESTTMP/doctor.err" >&2
  fi
  exit 1
}

assert_finding() { # id severity
  grep -q "\"id\":\"$1\",\"severity\":\"$2\",\"status\":\"fail\"" "$TESTTMP/out.jsonl" \
    || fail "expected finding $1 with severity=$2"
}

# All id matches include the terminating ,"severity" so an id that is a
# prefix of another id can never match the wrong finding.
assert_no_finding() { # id
  if grep "\"id\":\"$1\",\"severity\"" "$TESTTMP/out.jsonl" | grep -q '"status":"fail"'; then
    fail "unexpected finding $1"
  fi
}

assert_skipped() { # id reason
  grep "\"id\":\"$1\",\"severity\"" "$TESTTMP/out.jsonl" | grep '"status":"skipped"' | grep -qF "\"reason\":\"$2\"" \
    || fail "expected $1 to be skipped with reason=$2"
}

assert_data() { # id literal-fragment (searched on the finding's line)
  grep "\"id\":\"$1\",\"severity\"" "$TESTTMP/out.jsonl" | grep -qF "$2" \
    || fail "expected data fragment $2 on finding $1"
}

assert_exit() { # expected actual
  [ "$2" -eq "$1" ] || fail "expected exit $1, got $2"
}

assert_step() { # step-name done(true/false)
  grep -q "\"step\":\"$1\",\"done\":$2" "$TESTTMP/probe.json" \
    || fail "expected probe step $1 done=$2"
}

assert_step_data() { # step-name literal-fragment
  # Steps live on one JSON line; check the fragment appears after the step name
  # and before the next step entry.
  sed 's/{"step":/\n{"step":/g' "$TESTTMP/probe.json" | grep "\"step\":\"$1\"" | grep -qF "$2" \
    || fail "expected fragment $2 on probe step $1"
}

assert_probe_warning() { # literal-fragment
  grep -qF "$1" "$TESTTMP/probe.json" || fail "expected probe warning containing: $1"
}
