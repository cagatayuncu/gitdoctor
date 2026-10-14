#!/usr/bin/env bash
. "$(dirname "$0")/../../lib/harness.sh"

# integrations/gitbot/<slug>/ is published as bots/<slug>/ in gitbot-hq/Library.
# This replays the mechanical rules that Library's review rejects on
# (docs/bot-schema.md, CONTRIBUTING.md), so a publish PR never bounces on them.
BOTS="${BOT_DIR_OVERRIDE:-$SKILL_ROOT/integrations/gitbot}"
n=0
for dir in "$BOTS"/*/; do
  dir=${dir%/}
  slug=${dir##*/}
  n=$((n + 1))
  json="$dir/bot.json"

  for f in "$dir"/* "$dir"/.[!.]*; do
    [ -e "$f" ] || continue
    case "${f##*/}" in
      bot.json | instructions.md | setup.md) ;;
      *) fail "$slug: only bot.json, instructions.md and setup.md may be in the folder (found ${f##*/})" ;;
    esac
  done
  [ -f "$json" ] || fail "$slug: bot.json missing"
  [ -s "$dir/instructions.md" ] || fail "$slug: instructions.md missing or empty"

  body=$(tr '\n' ' ' <"$json")
  field() { # key -> first "key": "value" in bot.json
    local re="\"$1\"[[:space:]]*:[[:space:]]*\"([^\"]*)\""
    if [[ $body =~ $re ]]; then printf '%s' "${BASH_REMATCH[1]}"; fi
  }
  max() { # key limit
    local v; v=$(field "$1")
    [ -n "$v" ] || fail "$slug: $1 is required"
    [ "${#v}" -le "$2" ] || fail "$slug: $1 is ${#v} chars, limit $2"
  }
  one_of() { # key allowed...
    local v; v=$(field "$1"); shift
    case " $* " in *" $v "*) ;; *) fail "$slug: $v is not an allowed value" ;; esac
  }

  [ "$(field slug)" = "$slug" ] || fail "$slug: slug must equal the folder name"
  [[ $slug =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]] || fail "$slug: slug must be kebab-case"
  max name 24
  max description 80
  max examplePrompt 200
  about=$(field about)
  [ "${#about}" -ge 120 ] && [ "${#about}" -le 400 ] || fail "$slug: about is ${#about} chars, must be 120-400"
  one_of category "Code review" "Developer workflow" Releases Maintenance "Repository care" "Code exploration" Testing Documentation
  one_of agent claude-code opencode codex
  one_of permissionMode ask-permissions auto-approve plan
  one_of body bear belly birdy birdy-3 bunny burdy2 cat cloud doggy fire flower ghost heart moon rectangle star triangle tulip
  one_of color brand-sun brand-candy brand-ember brand-leaf brand-sky brand-honey
  one_of activity idle reading listening thinking working success error sleeping
  [ -n "$(field github)" ] || fail "$slug: author.github is required"
  [ -n "$(field emoji)" ] || fail "$slug: emoji is required"

  features=${body#*\"features\"*[}
  features=${features%%]*}
  count=0
  while [[ $features =~ \"([^\"]*)\" ]]; do
    count=$((count + 1))
    [ "${#BASH_REMATCH[1]}" -le 60 ] || fail "$slug: feature '${BASH_REMATCH[1]}' is over 60 chars"
    features=${features#*"${BASH_REMATCH[0]}"}
  done
  [ "$count" -eq 3 ] || fail "$slug: features must have exactly 3 entries, has $count"

  words=$(wc -w <"$dir/instructions.md")
  [ "$words" -le 600 ] || fail "$slug: instructions.md is $words words, limit ~600"
  IFS= read -r first <"$dir/instructions.md"
  case "$first" in "#"* | "---"*) fail "$slug: instructions.md must not start with a heading or frontmatter" ;; esac

  if grep -nE '/Users/[A-Za-z]|/home/[A-Za-z]|[A-Za-z]:[\\/]+Users[\\/]|gh[pousr]_[A-Za-z0-9]{20,}' "$dir"/*; then
    fail "$slug: machine-specific path or credential-shaped text"
  fi
done
[ "$n" -gt 0 ] || fail "no bot folders under $BOTS"
