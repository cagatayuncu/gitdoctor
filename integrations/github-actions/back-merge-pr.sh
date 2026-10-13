#!/usr/bin/env bash
# Opens ONE pull request that back-merges main into develop when the doctor
# finds a missing back-merge that is safe to hand to a reviewer:
# high-confidence ancestry, no predicted conflicts, and no open release
# already carrying main's commits (finish-hotfix.md § Back-merge target
# selection). The PR's head is a carrier branch (<backmerge prefix><main>,
# e.g. backmerge/main) at main's tip, so a conflict resolved on GitHub can
# never land on main. Re-runs fast-forward that carrier instead of opening a
# second PR; an open back-merge PR from any other carrier (a /gitdoctor finish
# in PR mode) is left alone. Merging stays a human decision.
#
# Usage: back-merge-pr.sh [--dry-run]
# Env:   GH_TOKEN; GITDOCTOR_PATH (optional: full path to gitflow-doctor.sh)
#        GITHUB_OUTPUT / GITHUB_ACTIONS / GITHUB_REPOSITORY inside Actions
# Needs: git + gh, origin's branches fetched first (the doctor runs --offline)
# Writes status=<status> and pr=<url> to $GITHUB_OUTPUT. Statuses (exit 0):
#   not-needed, skipped-unavailable (check could not run, or git < 2.38),
#   skipped-low-confidence, skipped-conflicts, skipped-release-open,
#   pr-exists, pr-updated, pr-opened,
#   would-open / would-update (--dry-run: nothing pushed, nothing opened)
# Exit 1: the doctor, git or gh failed, or a leftover carrier is in the way.
# Exit 2: usage.
set -u

USAGE="usage: back-merge-pr.sh [--dry-run]"
DRY_RUN=0
case "${1:-}" in
  "") ;;
  --dry-run) DRY_RUN=1 ;;
  -h | --help) echo "$USAGE"; exit 0 ;;
  *) echo "$USAGE" >&2; exit 2 ;;
esac

die() { echo "back-merge-pr: $*" >&2; exit 1; }

# Locating the doctor, first match wins:
#   1. $GITDOCTOR_PATH
#   2. ../../scripts/gitflow-doctor.sh (a gitdoctor checkout: the Action, the
#      Claude Code plugin)
#   3. the same directory: gitflow-doctor.sh (install.sh/.ps1 skill install)
#      or gitdoctor (Homebrew: bin/gitdoctor next to bin/gitdoctor-back-merge-pr)
#   4. gitdoctor or gitflow-doctor.sh on PATH
SELF_DIR=$(cd "$(dirname "$0")" 2>/dev/null && pwd)
DOCTOR=""
if [ -n "${GITDOCTOR_PATH:-}" ] && [ -f "$GITDOCTOR_PATH" ]; then
  DOCTOR=$GITDOCTOR_PATH
elif [ -n "$SELF_DIR" ]; then
  for cand in "$SELF_DIR/../../scripts/gitflow-doctor.sh" "$SELF_DIR/gitflow-doctor.sh" "$SELF_DIR/gitdoctor"; do
    if [ -f "$cand" ]; then DOCTOR=$cand; break; fi
  done
fi
if [ -z "$DOCTOR" ]; then
  DOCTOR=$(command -v gitdoctor 2>/dev/null || command -v gitflow-doctor.sh 2>/dev/null) \
    || die "gitflow-doctor.sh not found (install gitdoctor, or set GITDOCTOR_PATH)"
fi

finish() { # status [pr-url] [message]
  echo "gitdoctor back-merge: $1${3:+ - $3}${2:+ $2}"
  if [ -n "${GITHUB_OUTPUT:-}" ]; then
    printf 'status=%s\npr=%s\n' "$1" "${2:-}" >>"$GITHUB_OUTPUT"
  fi
  exit 0
}

warn_ci() { # message: an Actions annotation, so a skipped back-merge is seen
  if [ "${GITHUB_ACTIONS:-}" = true ]; then echo "::warning title=gitdoctor back-merge::$1"; fi
}

# varname json key -> first "key":"value" string ("" when absent). Locals are
# __-prefixed: printf -v into a caller's variable must not hit a local.
json_field_v() {
  local __re="\"$3\":\"([^\"]*)\""
  read -r "$1" </dev/null || true # clear first (bash 3.2: printf -v v '' leaves v unset)
  if [[ $2 =~ $__re ]]; then printf -v "$1" '%s' "${BASH_REMATCH[1]}"; fi
}

pr_url_v() { # varname pr-number
  if [ -n "${GITHUB_REPOSITORY:-}" ]; then
    printf -v "$1" '%s/%s/pull/%s' "${GITHUB_SERVER_URL:-https://github.com}" "$GITHUB_REPOSITORY" "$2"
  else
    printf -v "$1" '#%s' "$2"
  fi
}

REPORT=$(mktemp)
BODY=$(mktemp)
trap 'rm -f "$REPORT" "$BODY"' EXIT

# env-git-too-old rides along: below git 2.38 the doctor cannot predict
# conflicts, and its conflictsPredicted:false then means "never checked"
bash "$DOCTOR" --format jsonl --offline --checks missing-back-merge,back-merge-content-only,env-git-too-old >"$REPORT"
code=$?
[ "$code" -le 2 ] || die "the doctor failed (exit $code)"

FINDING=""
SKIPPED=""
GIT_TOO_OLD=""
HEADER=""
while IFS= read -r line; do
  case "$line" in
    '{"id":"missing-back-merge",'*'"status":"fail"'*) FINDING=$line ;;
    '{"id":"missing-back-merge",'*'"status":"skipped"'*) SKIPPED=$line ;;
    '{"id":"env-git-too-old",'*'"status":"fail"'*) GIT_TOO_OLD=$line ;;
    '{"gitflowDoctor":'*) HEADER=$line ;;
  esac
done <"$REPORT"
[ -n "$HEADER" ] || die "unexpected doctor output (no report header)"

json_field_v ROOT "$HEADER" root
[ -n "$ROOT" ] || die "not inside a git repository"
json_field_v MAIN "$HEADER" main
json_field_v DEVELOP "$HEADER" develop
json_field_v RELEASE_PREFIX "$HEADER" release
json_field_v BACKMERGE_PREFIX "$HEADER" backmerge
RELEASE_PREFIX=${RELEASE_PREFIX:-release/}
BACKMERGE_PREFIX=${BACKMERGE_PREFIX:-backmerge/}
CARRIER="$BACKMERGE_PREFIX$MAIN"
# by construction, never a write to main or develop
if [ "$CARRIER" = "$MAIN" ] || [ "$CARRIER" = "$DEVELOP" ]; then
  die "carrier $CARRIER would be $MAIN or $DEVELOP; check prefixes.backmerge"
fi

# --- gates: anything short of a clean, certain back-merge is reported only ---
if [ -n "$SKIPPED" ]; then
  json_field_v REASON "$SKIPPED" reason
  if [ "$REASON" != config-ignored ]; then warn_ci "missing-back-merge could not run ($REASON); check out with fetch-depth: 0 and fetch all branches"; fi
  finish skipped-unavailable "" "the check could not run: $REASON"
fi
[ -n "$FINDING" ] || finish not-needed "" "$DEVELOP already has everything on $MAIN"
if [ -n "$GIT_TOO_OLD" ]; then
  warn_ci "git < 2.38 cannot predict merge conflicts; upgrade git on the runner"
  finish skipped-unavailable "" "git < 2.38 cannot predict conflicts"
fi
case "$FINDING" in
  *'"confidence":"high"'*) ;;
  *)
    warn_ci "history is shallow or partial; check out with fetch-depth: 0 and re-run"
    finish skipped-low-confidence "" "ancestry is not certain (shallow history?)" ;;
esac
case "$FINDING" in
  *'"conflictsPredicted":false'*) ;;
  *)
    warn_ci "$MAIN -> $DEVELOP would conflict; back-merge locally (/gitdoctor finish, or fix-recipes.md#missing-back-merge)"
    finish skipped-conflicts "" "git predicts conflicts; resolve the back-merge locally" ;;
esac

MAIN_SHA=$(git rev-parse --verify -q "refs/remotes/origin/$MAIN^{commit}") || die "origin/$MAIN not found; fetch origin first"

REFS=$(git for-each-ref --contains "$MAIN_SHA" --format='%(refname)' refs/remotes/origin) || die "git for-each-ref failed"
while IFS= read -r ref; do
  case "$ref" in
    "refs/remotes/origin/$RELEASE_PREFIX"*)
      finish skipped-release-open "" "${ref#refs/remotes/origin/} already carries $MAIN's commits; they reach $DEVELOP when it finishes" ;;
  esac
done <<<"$REFS"

# --- an open back-merge PR (ours or a finish's) is reused, never doubled ------
# Fork PRs never count: their headRefName carries no owner, so a contributor's
# own `main` (or a fork branch named backmerge/x) would otherwise silence this.
command -v gh >/dev/null 2>&1 || die "gh not found"
PRS=$(gh pr list --state open --base "$DEVELOP" --limit 500 --json number,headRefName,baseRefName,isCrossRepository \
  --jq '.[] | "\(.number) \(.headRefName) \(.baseRefName) \(.isCrossRepository)"') || die "gh pr list failed"
OPEN_PR=""
OPEN_HEAD=""
while IFS=' ' read -r num head base cross; do
  if [ -z "$num" ] || [ "$base" != "$DEVELOP" ] || [ "$cross" = true ]; then continue; fi
  case "$head" in
    "$MAIN" | "$BACKMERGE_PREFIX"*) OPEN_PR=$num; OPEN_HEAD=$head; break ;;
  esac
done <<<"$PRS"

# The carrier is only ever fast-forwarded to main. Relative to main it is:
# none, at-main, behind (fast-forward possible), ahead ("Update branch" on
# GitHub merged develop into it) or diverged (ahead, and main moved since).
CARRIER_SHA=$(git rev-parse --verify -q "refs/remotes/origin/$CARRIER^{commit}") || CARRIER_SHA=""
if [ -z "$CARRIER_SHA" ]; then
  CARRIER_STATE=none
elif [ "$CARRIER_SHA" = "$MAIN_SHA" ]; then
  CARRIER_STATE=at-main
elif git merge-base --is-ancestor "$CARRIER_SHA" "$MAIN_SHA"; then
  CARRIER_STATE=behind
elif git merge-base --is-ancestor "$MAIN_SHA" "$CARRIER_SHA"; then
  CARRIER_STATE=ahead
else
  CARRIER_STATE=diverged
fi

push_carrier() {
  git push -q origin "$MAIN_SHA:refs/heads/$CARRIER" || die "pushing $CARRIER was rejected (origin/$CARRIER moved?); re-run after a fetch"
}

if [ -n "$OPEN_PR" ]; then
  pr_url_v URL "$OPEN_PR"
  [ "$OPEN_HEAD" = "$CARRIER" ] || finish pr-exists "$URL" "$OPEN_HEAD -> $DEVELOP is open"
  case "$CARRIER_STATE" in
    at-main | ahead) finish pr-exists "$URL" "$CARRIER already contains $MAIN" ;;
    diverged)
      warn_ci "$CARRIER has commits that are not on $MAIN and $MAIN moved on; the open PR lacks $MAIN's newest commits; merge it and delete $CARRIER, and the next run opens a fresh one"
      finish pr-exists "$URL" "$CARRIER diverged from $MAIN; left as is" ;;
  esac
  [ "$DRY_RUN" = 0 ] || finish would-update "$URL" "$CARRIER would move to $MAIN@${MAIN_SHA:0:7}"
  push_carrier
  finish pr-updated "$URL" "$CARRIER moved to $MAIN@${MAIN_SHA:0:7}"
fi

case "$CARRIER_STATE" in
  ahead | diverged) die "origin/$CARRIER has commits that are not on $MAIN (left from an earlier back-merge PR?); delete it, then re-run" ;;
esac
[ "$DRY_RUN" = 0 ] || finish would-open "" "$CARRIER ($MAIN@${MAIN_SHA:0:7}) -> $DEVELOP"
push_carrier

AHEAD=""
if [[ $FINDING =~ \"ahead\":([0-9]+) ]]; then AHEAD=${BASH_REMATCH[1]}; fi
# shellcheck disable=SC2016 # literal markdown backticks, nothing to expand
{
  printf '`%s` has %s commit(s) that never reached `%s` (gitdoctor `missing-back-merge`); the next release would silently revert them:\n\n' \
    "$MAIN" "${AHEAD:-some}" "$DEVELOP"
  git log --format='- %h %s' -n 20 "refs/remotes/origin/$DEVELOP..$MAIN_SHA"
  printf '\n**Merge with "Create a merge commit"**, not squash or rebase: only a merge commit makes `%s` an ancestor of `%s`. ' "$MAIN" "$DEVELOP"
  printf 'A squash leaves gitdoctor reporting `back-merge-content-only`.\n\n'
  printf -- '- Git predicted no conflicts (`git merge-tree`).\n'
  printf -- '- `%s` points at `%s` and carries nothing else; delete it after merging.\n' "$CARRIER" "$MAIN"
  printf -- '- Re-runs move this PR along with `%s` instead of opening another.\n\n' "$MAIN"
  printf '_Opened by [gitdoctor](https://github.com/cagatayuncu/gitdoctor)._\n'
} >"$BODY"

if ! OUT=$(gh pr create --base "$DEVELOP" --head "$CARRIER" --title "Back-merge $MAIN into $DEVELOP" --body-file "$BODY" 2>&1); then
  printf '%s\n' "$OUT" >&2
  case "$OUT" in
    *"not permitted to create"*)
      die "allow it under Settings > Actions > General > Workflow permissions: \"Allow GitHub Actions to create and approve pull requests\" ($CARRIER is pushed; a re-run opens the PR)" ;;
  esac
  die "gh pr create failed ($CARRIER is pushed; a re-run retries)"
fi
finish pr-opened "${OUT##*$'\n'}" "$CARRIER -> $DEVELOP"
