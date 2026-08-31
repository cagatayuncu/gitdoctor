#!/usr/bin/env bash
# gitdoctor watcher — cron-friendly single-shot scan with change detection.
# For repos with NO CI at all: run it from any machine that can fetch the repo.
#
#   */30 * * * * /path/to/gitdoctor-watch.sh /srv/checkouts/myrepo
#
# Usage: gitdoctor-watch.sh <repo-dir> [--webhook <url>] [--doctor <path>]
#
# On NEW critical findings (vs the previous run) it POSTs a Slack-compatible
# {"text": ...} payload to --webhook, or prints to stdout when no webhook is
# given (cron mails stdout by default). State lives in .git/gitdoctor-watch.state.
set -eu

REPO=${1:?usage: gitdoctor-watch.sh <repo-dir> [--webhook <url>] [--doctor <path>]}
shift
WEBHOOK=""
DOCTOR=""
while [ $# -gt 0 ]; do
  case "$1" in
    --webhook) WEBHOOK=${2:?}; shift 2 ;;
    --doctor) DOCTOR=${2:?}; shift 2 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done

if [ -z "$DOCTOR" ]; then
  if [ -f "$HOME/.claude/skills/gitdoctor/scripts/gitflow-doctor.sh" ]; then
    DOCTOR="$HOME/.claude/skills/gitdoctor/scripts/gitflow-doctor.sh"
  else
    DOCTOR=$(command -v gitflow-doctor.sh) || { echo "doctor script not found (--doctor)" >&2; exit 2; }
  fi
fi

cd "$REPO"
STATE=$(git rev-parse --git-path gitdoctor-watch.state)
REPORT=$(mktemp)
trap 'rm -f "$REPORT"' EXIT

set +e
bash "$DOCTOR" --format jsonl >"$REPORT" 2>/dev/null # fetch happens inside the doctor
status=$?
set -e

# stable fingerprint of current critical findings: "<id> <first data line>"
current=$(grep '"severity":"critical"' "$REPORT" | sed -n 's/.*"id":"\([^"]*\)".*"title":"\([^"]*\)".*/\1: \2/p' | sort)
previous=""
[ -f "$STATE" ] && previous=$(cat "$STATE")
printf '%s\n' "$current" >"$STATE"

new=$(comm -13 <(printf '%s\n' "$previous") <(printf '%s\n' "$current") | grep . || true)
[ -z "$new" ] && exit 0

msg="gitdoctor ($(basename "$REPO")): new critical finding(s):
$new"

if [ -n "$WEBHOOK" ]; then
  payload=$(printf '%s' "$msg" | sed 's/\\/\\\\/g; s/"/\\"/g' | awk '{printf "%s\\n", $0}')
  curl -sS -X POST -H 'Content-Type: application/json' -d "{\"text\":\"$payload\"}" "$WEBHOOK" >/dev/null
else
  printf '%s\n' "$msg"
fi
[ "$status" -ge 2 ] && exit 0 # criticals were reported, the watcher itself succeeded
exit 0
