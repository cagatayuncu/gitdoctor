#!/usr/bin/env bash
# Turns a gitdoctor JSON report into a PR comment (created once, then updated
# in place on every push — no comment spam).
#
# Usage: comment.sh <report.json> <pr-number>
# Env:   GH_TOKEN (the workflow's github.token), GITHUB_REPOSITORY
# Needs: gh + jq (both preinstalled on GitHub-hosted runners)
set -eu

REPORT=${1:?usage: comment.sh <report.json> <pr-number>}
PR=${2:?usage: comment.sh <report.json> <pr-number>}
MARKER='<!-- gitdoctor-report -->'

crit=$(jq -r '.summary.critical' "$REPORT")
warn=$(jq -r '.summary.warning' "$REPORT")
info=$(jq -r '.summary.info' "$REPORT")
ok=$(jq -r '.summary.ok' "$REPORT")

BODY=$(mktemp)
{
  printf '%s\n' "$MARKER"
  if [ "$crit" -gt 0 ]; then
    printf '## 🔴 gitdoctor: %s critical finding(s)\n\n' "$crit"
  elif [ "$warn" -gt 0 ]; then
    printf '## 🟡 gitdoctor: %s warning(s)\n\n' "$warn"
  else
    printf '## 🟢 gitdoctor: clean\n\n'
  fi
  printf '`%s critical · %s warning · %s info · %s ok`\n\n' "$crit" "$warn" "$info" "$ok"

  if jq -e '.findings | length > 0' "$REPORT" >/dev/null; then
    printf '| | Check | Finding |\n|---|---|---|\n'
    jq -r '.findings[] | select(.status == "fail")
      | "| " + (if .severity == "critical" then "🔴" elif .severity == "warning" then "🟡" else "🔵" end)
      + " | `" + .id + "` | " + (.title | gsub("\\|"; "\\\\|")) + " |"' "$REPORT" | head -40

    printf '\n<details><summary>Fix commands</summary>\n\n'
    jq -r '.findings[] | select(.status == "fail")
      | "**" + .id + "**\n```bash\n" + (.fix.commands | join("\n")) + "\n```\n"' "$REPORT" | head -120
    printf '\n</details>\n'
  fi
  printf '\n_[gitdoctor](https://github.com/cagatayuncu/gitdoctor) · read-only scan · recipes: references/fix-recipes.md_\n'
} >"$BODY"

existing=$(gh api "repos/$GITHUB_REPOSITORY/issues/$PR/comments" --paginate \
  --jq ".[] | select(.body | startswith(\"$MARKER\")) | .id" | head -1)

if [ -n "$existing" ]; then
  gh api -X PATCH "repos/$GITHUB_REPOSITORY/issues/comments/$existing" -f body="$(cat "$BODY")" >/dev/null
  echo "updated comment $existing"
else
  gh pr comment "$PR" --body-file "$BODY" >/dev/null
  echo "created comment"
fi
