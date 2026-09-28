#!/usr/bin/env bash
. "$(dirname "$0")/../../lib/harness.sh"

# --merge-proof: evidence that a staged conflict resolution is exactly
# "ours + their change" (and "theirs + our change"), with line endings,
# BOM and leftover markers checked. Read-only; the user decides.
proof() { # literal fragment expected in the proof JSON
  grep -qF "$1" "$TESTTMP/proof.json" || { cat "$TESTTMP/proof.json" >&2; fail "expected merge-proof fragment $1"; }
}
run_proof() {
  bash "$DOCTOR" --offline --merge-proof >"$TESTTMP/proof.json" 2>"$TESTTMP/doctor.err" || fail "--merge-proof must exit 0"
}

mkrepo
run_proof
proof '"mergeProof":{"merging":false}'

printf 'a\n<!-- comment -->\nb\n' >web.config
git add web.config && git commit -qm "chore: web.config"
git switch -qc hotfix/1.0.1
printf 'a\n<rule/>\n<!-- comment -->\nb\n' >web.config
git commit -qam "fix: add a rule above the comment"
git switch -q main
printf 'a\nb\n' >web.config
git commit -qam "chore: drop the comment"

if git merge -q --no-ff hotfix/1.0.1 -m "Release 1.0.1" 2>/dev/null; then fail "fixture must conflict"; fi
run_proof
proof '"merging":true'
proof '{"path":"web.config","state":"unresolved"'

# the union: main's deletion plus the hotfix's new line
printf 'a\n<rule/>\nb\n' >web.config
git add web.config
run_proof
proof '{"path":"web.config","state":"resolved","oursPlusTheirChange":true,"theirsPlusOurChange":true,"markers":false,"eolPreserved":true,"bomPreserved":true,"validator":"xml","verdict":"consistent"}'

# keeping only one side drops the other side's change -> review
printf 'a\nb\n' >web.config
git add web.config
run_proof
proof '"oursPlusTheirChange":false'
proof '"verdict":"review"'

# right content but CRLF line endings -> review
printf 'a\r\n<rule/>\r\nb\r\n' >web.config
git add web.config
run_proof
proof '"eolPreserved":false'
proof '"verdict":"review"'

# a leftover marker -> review
printf 'a\n<rule/>\n=======\nb\n' >web.config
git add web.config
run_proof
proof '"markers":true'

git merge --abort
run_proof
proof '"merging":false'
