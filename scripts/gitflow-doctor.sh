#!/usr/bin/env bash
# gitflow-doctor.sh — read-only Git Flow diagnostics and finish probes.
#
# Emits findings describing anomalies and alignment problems in a classic
# git-flow repository (main + develop + feature/release/hotfix) as JSON (the
# agent contract), JSON Lines, human text, Markdown, SARIF (code scanning) or a
# baseline (ignoreFindings entries for .gitflow.json).
# The ONLY mutation this script may perform is a remote-tracking cache
# refresh (`git fetch origin --prune --tags`); disable it with --offline
# or --no-fetch. Every other command is plumbing reads.
#
# Exit codes: 0 clean/info-only, 1 warnings, 2 criticals, 4 usage.
#
# Portability: bash 3.2+ (Git Bash on Windows, macOS, Linux). No jq — JSON is
# emitted by hand. gh is optional; gh-backed checks degrade to status:"skipped".
#
# Performance contract: process spawns are expensive on Windows, so all ref/tag
# data is loaded ONCE via for-each-ref into memory and every lookup after that
# is pure bash. Command output is captured with `read < <(cmd)` (one process)
# instead of `$(cmd)` (fork + process). Keep it that way when editing.

set -u
set -f # no pathname expansion: ref names may contain *?[ and several list
       # expansions are deliberately unquoted for zero-fork word-splitting
LC_ALL=C
export LC_ALL

DOCTOR_VERSION="0.3.0"
SEMVER_RE='^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?(\+[0-9A-Za-z.-]+)?$'
RELEASE_NAME_RE='^[0-9]+\.[0-9]+\.[0-9]+$'
RELEASE_NAME_PRE_RE='^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$'

# ---------------------------------------------------------------------------
# Defaults (CLI flags > .gitflow.json sed-fallback > these)
# ---------------------------------------------------------------------------
FORMAT="json"
EXPLAIN=""
LIST_CHECKS=0
CHANGELOG_FILE=""
GITHUB_RELEASE=1
REQUIRE_SIGNED_TAGS=0
HOMEBREW_TAP=""
HOMEBREW_FORMULA=""
OFFLINE=0
DO_FETCH=1
NOW=""
ONLY_CHECKS=""
SKIP_CHECKS=""
MIN_SEVERITY="info"
MAIN=""
DEVELOP=""
TAG_PREFIX="__UNSET__"
FEATURE_PREFIX="feature/"
RELEASE_PREFIX="release/"
HOTFIX_PREFIX="hotfix/"
BACKMERGE_PREFIX="backmerge/"
STALE_DAYS=""
SCAN_DEPTH=""
MAX_RELEASES=""
IGNORE_BRANCHES="dependabot/*,renovate/*,gh-pages"
IGNORE_TAGS=""
IGNORE_SHAS=""
IGNORE_FINDINGS=""
ASSUME_GITHUB=""
ALLOW_PRERELEASE=0
VERSION_SCHEME=""
HOTFIX_PATTERN=""
HOTFIX_INFIX=""
MERGE_MODE="auto"
CONVENTIONS=0
MERGE_PROOF=0
WORKSPACE=""
WS_TAG=""
WS_POLICY=""
WS_PASS=""
PROBE=""
PROBE_BRANCH=""
PROBE_VERSION=""
VF_PATHS=""
VF_PATTERNS=""
VF_COUNT=0

usage() {
  cat <<'EOF'
usage: gitflow-doctor.sh [options]
  --format FORMAT            json (default) | jsonl | text | markdown | sarif | baseline
                             (probes always emit JSON; baseline always exits 0)
  --explain CHECK-ID         print the fix recipe for one check and exit
  --list-checks              print every check id and exit
  --offline                  no fetch, no gh, no network ls-remote
  --no-fetch                 skip the fetch but keep gh/ls-remote
  --now EPOCH                clock override for time-based checks
  --checks id,id             run only these checks
  --skip id,id               skip these checks
  --min-severity LEVEL       info|warning|critical (default info)
  --main NAME --develop NAME --tag-prefix P
  --feature-prefix P --release-prefix P --hotfix-prefix P --backmerge-prefix P
  --stale-days N --scan-depth N --max-releases N
  --merge-mode auto|pr|local
  --ignore-branches globs --ignore-tags globs --ignore-shas list
  --ignore-findings list     entries: "check-id" or "check-id:key" (key = the sha,
                             branch, tag, file or PR the finding names; see --format baseline)
  --version-file PATH --version-pattern ERE   (repeatable, paired; POSIX ERE
                             matched per line, capture group 1 = version)
  --allow-prerelease         accept x.y.z-suffix in release/hotfix branch names
  --version-scheme S         semver (default) | suffix-counter (hotfixes are
                             post-releases X.Y.Z<infix>N that sort after X.Y.Z)
  --hotfix-pattern P         suffix-counter hotfix version, default {base}-hotfix.{n}
  --changelog PATH           changelog file (enables changelog-tag-mismatch)
  --no-github-release        repo does not publish GitHub Releases (skips gh-release-missing-for-tag)
  --require-signed-tags      release tags must be GPG/SSH signed (enables tag-unsigned)
  --homebrew-tap owner/repo --homebrew-formula PATH
                             Homebrew tap that ships this repo (enables the
                             homebrew-formula-stale check and the finish probe step)
  --assume-github owner/repo force GitHub mode even for non-github origin (tests)
  --probe finish-release|finish-hotfix|finish-feature --branch B [--version V]
  --conventions              infer tag/message/back-merge conventions from the
                             newest release/hotfix tags on main (JSON) and exit
  --merge-proof              during a conflicted merge: evidence per conflicted file
                             that the staged resolution keeps both sides (JSON) and exit
  --workspace FILE [--branch B] [--tag T]
                             several repos in lockstep (.gitflow-workspace.json): per-repo
                             doctor summary, finish probe for B, tag consistency for T
EOF
}

die_usage() { echo "gitflow-doctor: $1" >&2; usage >&2; exit 4; }

NL=$'\n'

while [ $# -gt 0 ]; do
  case "$1" in
    --format) FORMAT=${2:?}; shift 2 ;;
    --explain) EXPLAIN=${2:?}; shift 2 ;;
    --list-checks) LIST_CHECKS=1; shift ;;
    --changelog) CHANGELOG_FILE=${2:?}; shift 2 ;;
    --no-github-release) GITHUB_RELEASE=0; shift ;;
    --require-signed-tags) REQUIRE_SIGNED_TAGS=1; shift ;;
    --homebrew-tap) HOMEBREW_TAP=${2:?}; shift 2 ;;
    --homebrew-formula) HOMEBREW_FORMULA=${2:?}; shift 2 ;;
    --offline) OFFLINE=1; shift ;;
    --no-fetch) DO_FETCH=0; shift ;;
    --now) NOW=${2:?}; shift 2 ;;
    --checks) ONLY_CHECKS=${2:?}; shift 2 ;;
    --skip) SKIP_CHECKS=${2:?}; shift 2 ;;
    --min-severity) MIN_SEVERITY=${2:?}; shift 2 ;;
    --main) MAIN=${2:?}; shift 2 ;;
    --develop) DEVELOP=${2:?}; shift 2 ;;
    --tag-prefix) TAG_PREFIX=${2-}; shift 2 ;;
    --feature-prefix) FEATURE_PREFIX=${2:?}; shift 2 ;;
    --release-prefix) RELEASE_PREFIX=${2:?}; shift 2 ;;
    --hotfix-prefix) HOTFIX_PREFIX=${2:?}; shift 2 ;;
    --backmerge-prefix) BACKMERGE_PREFIX=${2:?}; shift 2 ;;
    --stale-days) STALE_DAYS=${2:?}; shift 2 ;;
    --scan-depth) SCAN_DEPTH=${2:?}; shift 2 ;;
    --max-releases) MAX_RELEASES=${2:?}; shift 2 ;;
    --merge-mode) MERGE_MODE=${2:?}; shift 2 ;;
    --ignore-branches) IGNORE_BRANCHES=${2-}; shift 2 ;;
    --ignore-tags) IGNORE_TAGS=${2-}; shift 2 ;;
    --ignore-shas) IGNORE_SHAS=${2-}; shift 2 ;;
    --ignore-findings) IGNORE_FINDINGS=${2-}; shift 2 ;;
    --version-file) VF_PATHS="$VF_PATHS${VF_PATHS:+$NL}${2:?}"; shift 2 ;;
    --version-pattern) VF_PATTERNS="$VF_PATTERNS${VF_PATTERNS:+$NL}${2:?}"; VF_COUNT=$((VF_COUNT + 1)); shift 2 ;;
    --allow-prerelease) ALLOW_PRERELEASE=1; shift ;;
    --version-scheme) VERSION_SCHEME=${2:?}; shift 2 ;;
    --hotfix-pattern) HOTFIX_PATTERN=${2:?}; shift 2 ;;
    --assume-github) ASSUME_GITHUB=${2:?}; shift 2 ;;
    --conventions) CONVENTIONS=1; shift ;;
    --merge-proof) MERGE_PROOF=1; shift ;;
    --workspace) WORKSPACE=${2:?}; shift 2 ;;
    --tag) WS_TAG=${2:?}; shift 2 ;;
    --probe) PROBE=${2:?}; shift 2 ;;
    --branch) PROBE_BRANCH=${2:?}; shift 2 ;;
    --version) PROBE_VERSION=${2:?}; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) die_usage "unknown option: $1" ;;
  esac
done

case "$FORMAT" in json|jsonl|text|markdown|sarif|baseline) : ;; *) die_usage "--format must be json, jsonl, text, markdown, sarif or baseline" ;; esac
case "$VERSION_SCHEME" in ''|semver|suffix-counter) : ;; *) die_usage "--version-scheme must be semver or suffix-counter" ;; esac

# ---------------------------------------------------------------------------
# Check catalog (the authoritative id list; README/action counts derive from it)
# ---------------------------------------------------------------------------
ALL_CHECK_IDS="env-not-a-repo env-no-origin env-origin-not-github env-gh-unavailable env-fetch-failed env-missing-main env-missing-develop env-shallow-clone env-git-too-old dirty-worktree detached-head operation-in-progress sync-behind sync-ahead sync-diverged missing-back-merge back-merge-content-only untagged-merge-on-main direct-commit-on-main wrong-base-feature wrong-base-hotfix release-develop-drift flow-branch-behind-main multiple-release-branches multiple-hotfix-branches orphaned-release-branch orphaned-hotfix-branch release-version-collision version-file-tag-mismatch changelog-tag-mismatch tag-not-on-main non-semver-tag duplicate-tag-target tag-prefix-collision tag-lightweight-release tag-unsigned tag-unpushed tag-sha-mismatch branch-stale-merged branch-stale-inactive branch-bad-version-name branch-unrecognized gh-protection-missing-main gh-protection-missing-develop gh-default-branch-unexpected gh-open-pr-wrong-base gh-squash-only-back-merge-limitation gh-release-missing-for-tag homebrew-formula-stale tag-convention-drift workspace-repo-missing"
RECIPES_URL="https://github.com/cagatayuncu/gitdoctor/blob/main/references/fix-recipes.md"

known_check_id() { case " $ALL_CHECK_IDS " in *" $1 "*) return 0 ;; esac; return 1; }
validate_check_list() { # flag-name comma-list
  local rest="$2," id
  while [ -n "$rest" ]; do
    id=${rest%%,*}; rest=${rest#*,}
    [ -z "$id" ] && continue
    known_check_id "$id" || die_usage "$1: unknown check id '$id' (see --list-checks)"
  done
}
[ -n "$ONLY_CHECKS" ] && validate_check_list --checks "$ONLY_CHECKS"
[ -n "$SKIP_CHECKS" ] && validate_check_list --skip "$SKIP_CHECKS"

if [ "$LIST_CHECKS" = 1 ]; then
  for id in $ALL_CHECK_IDS; do printf '%s\n' "$id"; done
  exit 0
fi

recipe_anchor_v() { # varname check-id -> anchor in fix-recipes.md (a few ids share a recipe)
  case "$2" in
    back-merge-content-only) printf -v "$1" 'missing-back-merge' ;;
    orphaned-hotfix-branch) printf -v "$1" 'orphaned-release-branch' ;;
    *) printf -v "$1" '%s' "$2" ;;
  esac
}

if [ -n "$EXPLAIN" ]; then
  known_check_id "$EXPLAIN" || die_usage "--explain: unknown check id '$EXPLAIN' (see --list-checks)"
  recipe_anchor_v anchor "$EXPLAIN"
  script_dir=${BASH_SOURCE[0]%/*}
  [ "$script_dir" = "${BASH_SOURCE[0]}" ] && script_dir=.
  recipes_file="$script_dir/../references/fix-recipes.md"
  if [ ! -f "$recipes_file" ]; then
    # shellcheck disable=SC2154 # anchor is assigned via printf -v inside recipe_anchor_v
    printf 'recipe file not found next to this script (%s)\nread it online: %s#%s\n' "$recipes_file" "$RECIPES_URL" "$anchor"
    exit 0
  fi
  printing=0; found=0
  while IFS= read -r line || [ -n "$line" ]; do
    line=${line%$'\r'}
    case "$line" in
      "## $anchor") printing=1; found=1 ;;
      "## "*) [ "$printing" = 1 ] && break ;;
    esac
    [ "$printing" = 1 ] && printf '%s\n' "$line"
  done <"$recipes_file"
  [ "$found" = 1 ] || { echo "gitflow-doctor: no recipe section '## $anchor' in $recipes_file" >&2; exit 4; }
  printf '(online: %s#%s)\n' "$RECIPES_URL" "$anchor"
  exit 0
fi
case "$MIN_SEVERITY" in
  info) MIN_RANK=1 ;;
  warning) MIN_RANK=2 ;;
  critical) MIN_RANK=3 ;;
  *) die_usage "bad --min-severity" ;;
esac
if [ -n "$PROBE" ]; then
  case "$PROBE" in finish-release|finish-hotfix|finish-feature) : ;; *) die_usage "bad --probe" ;; esac
  [ -z "$PROBE_BRANCH" ] && die_usage "--probe requires --branch"
  case "$PROBE" in
    finish-release|finish-hotfix) [ -z "$PROBE_VERSION" ] && die_usage "$PROBE requires --version" ;;
  esac
fi
[ "$OFFLINE" = 1 ] && DO_FETCH=0
if [ -z "$NOW" ]; then IFS= read -r NOW < <(date +%s) || NOW=0; fi

# ---------------------------------------------------------------------------
# Zero-fork capture + JSON helpers
# ---------------------------------------------------------------------------
capture() { # varname cmd...  (first output line; empty on failure/no output)
  # `|| [ -n ... ]` / pre-init keep data that arrives WITHOUT a trailing
  # newline (read returns non-zero at EOF but has already assigned the text —
  # e.g. a VERSION file written with `printf '1.2.3'`).
  local __v=$1 __out=""; shift
  IFS= read -r __out < <("$@" 2>/dev/null) || :
  printf -v "$__v" '%s' "$__out"
}

capture_all() { # varname cmd...  (all output lines, newline-joined, no trailing NL)
  local __v=$1 __line __acc=""; shift
  while IFS= read -r __line || [ -n "$__line" ]; do
    __acc="$__acc${__acc:+$NL}$__line"
  done < <("$@" 2>/dev/null)
  printf -v "$__v" '%s' "$__acc"
}

clear_v() { # varname — assign the empty string. NOT `printf -v v ''`: bash 3.2 (macOS)
  # leaves the variable unset when the formatted result is empty, and `set -u`
  # then aborts on the first read. `read` at EOF assigns "" on every bash.
  IFS= read -r "$1" </dev/null || :
}

json_str_v() { # varname value — JSON-escape into varname
  local s=$2
  s=${s//\\/\\\\}
  s=${s//\"/\\\"}
  s=${s//$'\r'/\\r}
  s=${s//$'\n'/\\n}
  s=${s//$'\t'/\\t}
  printf -v "$1" '%s' "$s"
}

json_arr_v() { # varname items... -> ["a","b"]
  local __v=$1 __out="" __e x; shift
  for x in "$@"; do
    json_str_v __e "$x"
    __out="$__out${__out:+,}\"$__e\""
  done
  printf -v "$__v" '[%s]' "$__out"
}

count_lines_v() { # varname multiline-string
  local __v=$1 __n=0 __line
  while IFS= read -r __line; do [ -n "$__line" ] && __n=$((__n + 1)); done <<<"$2"
  printf -v "$__v" '%s' "$__n"
}

# ---------------------------------------------------------------------------
# Finding accumulation
# ---------------------------------------------------------------------------
FINDINGS=""
REC_LINES=""   # renderer records: kind US id US severity US title US confidence US recipe US key US fix-json|reason
US=$'\x1f'
N_CRIT=0; N_WARN=0; N_INFO=0; N_OK=0; N_SKIP=0
WORST=0

check_enabled() {
  local id=$1
  if [ -n "$ONLY_CHECKS" ]; then
    case ",$ONLY_CHECKS," in *",$id,"*) : ;; *) return 1 ;; esac
  fi
  case ",$SKIP_CHECKS," in *",$id,"*) return 1 ;; esac
  return 0
}

any_enabled() { # section gate: run shared prep only if a consumer check is on
  local id
  for id in "$@"; do check_enabled "$id" && return 0; done
  return 1
}

ignored_finding() { # id [sha]
  local id=$1 sha=${2:-}
  [ -z "$IGNORE_FINDINGS" ] && return 1
  case ",$IGNORE_FINDINGS," in
    *",$id,"*) return 0 ;;
  esac
  if [ -n "$sha" ]; then
    case ",$IGNORE_FINDINGS," in *",$id:$sha,"*) return 0 ;; esac
  fi
  return 1
}

glob_in_list() { # value comma-separated-globs
  local v=$1 g rest=$2
  [ -z "$rest" ] && return 1
  rest="$rest,"
  while [ -n "$rest" ]; do
    g=${rest%%,*}; rest=${rest#*,}
    [ -z "$g" ] && continue
    # shellcheck disable=SC2254
    case "$v" in $g) return 0 ;; esac
  done
  return 1
}

fail_check() { # id severity title data_fragment fix_cmds_json recipe_anchor [confidence] [key]
  # key = the sha/branch/tag/file/PR the finding is about; enables
  # "id:key" suppression in --ignore-findings and --format baseline entries.
  local id=$1 sev=$2 title=$3 data=${4:-} fixcmds=${5:-[]} recipe=${6:-$1} conf=${7:-high} sha=${8:-}
  check_enabled "$id" || return 0
  if ignored_finding "$id" "$sha"; then skip_check "$id" "config-ignored" "check skipped" "$sha"; return 0; fi
  local rank=1
  case "$sev" in critical) rank=3 ;; warning) rank=2 ;; esac
  if [ "$rank" -lt "$MIN_RANK" ]; then N_OK=$((N_OK + 1)); return 0; fi
  case "$sev" in
    critical) N_CRIT=$((N_CRIT + 1)) ;;
    warning) N_WARN=$((N_WARN + 1)) ;;
    info) N_INFO=$((N_INFO + 1)) ;;
  esac
  [ "$rank" -gt "$WORST" ] && WORST=$rank
  local jt obj
  json_str_v jt "$title"
  obj="{\"id\":\"$id\",\"severity\":\"$sev\",\"status\":\"fail\",\"title\":\"$jt\""
  [ -n "$data" ] && obj="$obj,\"data\":{$data}"
  obj="$obj,\"fix\":{\"commands\":$fixcmds,\"recipeRef\":\"references/fix-recipes.md#$recipe\"}"
  obj="$obj,\"confidence\":\"$conf\""
  if [ -n "$sha" ]; then local jk; json_str_v jk "$sha"; obj="$obj,\"key\":\"$jk\""; fi
  obj="$obj}"
  FINDINGS="$FINDINGS${FINDINGS:+$NL}$obj"
  REC_LINES="$REC_LINES${REC_LINES:+$NL}fail$US$id$US$sev$US${title//$NL/ }$US$conf$US$recipe$US$sha$US$fixcmds"
}

ok_check() { check_enabled "$1" || return 0; N_OK=$((N_OK + 1)); }

skip_check() { # id reason [title] [key]
  local id=$1 reason=$2 title=${3:-check skipped} key=${4:-} jt
  check_enabled "$id" || return 0
  N_SKIP=$((N_SKIP + 1))
  json_str_v jt "$title"
  FINDINGS="$FINDINGS${FINDINGS:+$NL}{\"id\":\"$id\",\"severity\":\"info\",\"status\":\"skipped\",\"title\":\"$jt\",\"data\":{\"reason\":\"$reason\"}}"
  REC_LINES="$REC_LINES${REC_LINES:+$NL}skip$US$id${US}info$US$title$US$US$US$key$US$reason"
}

json_arr_unpack_v() { # varname json-array-of-strings -> newline list (inverse of json_arr_v)
  local __ju_v=$1 __ju_s=$2 __ju_out="" __ju_item
  __ju_s=${__ju_s#[}; __ju_s=${__ju_s%]}
  if [ -z "$__ju_s" ]; then clear_v "$__ju_v"; return; fi
  __ju_s=${__ju_s#\"}; __ju_s=${__ju_s%\"}
  while :; do
    case "$__ju_s" in
      *'","'*) __ju_item=${__ju_s%%'","'*}; __ju_s=${__ju_s#*'","'} ;;
      *) __ju_item=$__ju_s; __ju_s="" ;;
    esac
    __ju_item=${__ju_item//\\\"/\"}
    __ju_item=${__ju_item//\\n/$NL}
    __ju_item=${__ju_item//\\t/$'\t'}
    __ju_item=${__ju_item//\\\\/\\}
    __ju_out="$__ju_out${__ju_out:+$NL}$__ju_item"
    [ -z "$__ju_s" ] && break
  done
  printf -v "$__ju_v" '%s' "$__ju_out"
}

render_text() {
  local rec kind id sev title conf recipe key fix cmds c label
  printf 'gitdoctor %s  %s\n' "$DOCTOR_VERSION" "${REPO_ROOT:-$PWD}"
  printf 'main: %s  develop: %s  github: %s  merge-mode: %s (main=%s, develop=%s)\n\n' \
    "${MAIN:-?}" "${DEVELOP:-?}" "${SLUG:--}" "$MERGE_MODE" "${RESOLVED_MAIN_MODE:-unknown}" "${RESOLVED_DEV_MODE:-unknown}"
  [ -n "${LATEST_TAG:-}" ] && printf 'latest tag: %s (%s)  next hotfix: %s\n\n' "$LATEST_TAG" "$VERSION_SCHEME" "${NEXT_HOTFIX:--}"
  [ -z "$REC_LINES" ] && printf 'no findings\n'
  while IFS="$US" read -r kind id sev title conf recipe key fix; do
    [ -z "$kind" ] && continue
    if [ "$kind" = skip ]; then
      printf 'SKIP  %s  (%s)\n' "$id" "$fix"
      continue
    fi
    case "$sev" in critical) label=CRIT ;; warning) label=WARN ;; *) label=INFO ;; esac
    printf '%s  %s  %s\n' "$label" "$id" "$title"
    json_arr_unpack_v cmds "$fix"
    c="fix:"
    while IFS= read -r rec; do
      [ -z "$rec" ] && continue
      printf '      %-4s %s\n' "$c" "$rec"; c=""
    done <<<"$cmds"
    printf '      recipe: references/fix-recipes.md#%s' "$recipe"
    [ "$conf" != high ] && printf '   (confidence: %s)' "$conf"
    printf '\n'
  done <<<"$REC_LINES"
  printf '\n%s critical, %s warning, %s info, %s ok, %s skipped\n' "$N_CRIT" "$N_WARN" "$N_INFO" "$N_OK" "$N_SKIP"
}

render_markdown() {
  local kind id sev title conf recipe key fix cmds icon
  if [ "$N_CRIT" -gt 0 ]; then printf '## :red_circle: gitdoctor: %s critical finding(s)\n\n' "$N_CRIT"
  elif [ "$N_WARN" -gt 0 ]; then printf '## :yellow_circle: gitdoctor: %s warning(s)\n\n' "$N_WARN"
  else printf '## :green_circle: gitdoctor: clean\n\n'; fi
  # shellcheck disable=SC2016 # literal markdown backticks
  printf '`%s critical · %s warning · %s info · %s ok · %s skipped`\n\n' "$N_CRIT" "$N_WARN" "$N_INFO" "$N_OK" "$N_SKIP"
  if [ $((N_CRIT + N_WARN + N_INFO)) -gt 0 ]; then
    printf '| | Check | Finding |\n|---|---|---|\n'
    while IFS="$US" read -r kind id sev title conf recipe key fix; do
      [ "$kind" = fail ] || continue
      case "$sev" in critical) icon=':red_circle:' ;; warning) icon=':yellow_circle:' ;; *) icon=':large_blue_circle:' ;; esac
      title=${title//|/\\|}
      # shellcheck disable=SC2016 # literal markdown backticks
      printf '| %s | `%s` | %s |\n' "$icon" "$id" "$title"
    done <<<"$REC_LINES"
    printf '\n<details><summary>Fix commands</summary>\n\n'
    while IFS="$US" read -r kind id sev title conf recipe key fix; do
      [ "$kind" = fail ] || continue
      json_arr_unpack_v cmds "$fix"
      # shellcheck disable=SC2016 # literal markdown code fence
      printf '**%s** ([recipe](%s#%s))\n```bash\n%s\n```\n\n' "$id" "$RECIPES_URL" "$recipe" "$cmds"
    done <<<"$REC_LINES"
    printf '</details>\n'
  fi
  printf '\n_[gitdoctor](https://github.com/cagatayuncu/gitdoctor) %s · read-only scan_\n' "$DOCTOR_VERSION"
}

render_sarif() {
  local kind id sev title conf recipe key fix cmds level rules="" results="" seen=" " jt jc jk jr msg
  while IFS="$US" read -r kind id sev title conf recipe key fix; do
    [ "$kind" = fail ] || continue
    case "$sev" in critical) level=error ;; warning) level=warning ;; *) level=note ;; esac
    case "$seen" in
      *" $id "*) : ;;
      *)
        seen="$seen$id "
        rules="$rules${rules:+,}{\"id\":\"$id\",\"name\":\"$id\",\"shortDescription\":{\"text\":\"$id\"},\"helpUri\":\"$RECIPES_URL#$recipe\",\"defaultConfiguration\":{\"level\":\"$level\"}}" ;;
    esac
    json_arr_unpack_v cmds "$fix"
    msg=$title
    [ -n "$cmds" ] && msg="$title$NL${NL}Fix:$NL$cmds"
    json_str_v jt "$msg"; json_str_v jk "$key"; json_str_v jc "$conf"
    jr="{\"ruleId\":\"$id\",\"level\":\"$level\",\"message\":{\"text\":\"$jt\"}"
    jr="$jr,\"locations\":[{\"physicalLocation\":{\"artifactLocation\":{\"uri\":\".gitflow.json\",\"uriBaseId\":\"%SRCROOT%\"},\"region\":{\"startLine\":1}}}]"
    jr="$jr,\"partialFingerprints\":{\"gitdoctorKey\":\"$id:${jk:--}\"},\"properties\":{\"confidence\":\"$jc\",\"key\":\"$jk\"}}"
    results="$results${results:+,}$jr"
  done <<<"$REC_LINES"
  # shellcheck disable=SC2016 # "$schema" is a literal SARIF key
  printf '{"$schema":"https://json.schemastore.org/sarif-2.1.0.json","version":"2.1.0","runs":[{"tool":{"driver":{"name":"gitdoctor","version":"%s","informationUri":"https://github.com/cagatayuncu/gitdoctor","rules":[%s]}},"invocations":[{"executionSuccessful":true}],"results":[%s]}]}\n' \
    "$DOCTOR_VERSION" "$rules" "$results"
}

render_baseline() { # every failing finding as an ignoreFindings entry, plus the entries already configured
  local kind id sev title conf recipe key fix entry seen=" " out="" je rest
  rest="$IGNORE_FINDINGS,"
  while [ -n "$rest" ]; do
    entry=${rest%%,*}; rest=${rest#*,}
    [ -z "$entry" ] && continue
    case "$seen" in *" $entry "*) continue ;; esac
    seen="$seen$entry "; json_str_v je "$entry"; out="$out${out:+,}\"$je\""
  done
  while IFS="$US" read -r kind id sev title conf recipe key fix; do
    [ -z "$kind" ] && continue
    case "$kind" in fail) : ;; skip) [ "$fix" = config-ignored ] || continue ;; *) continue ;; esac
    entry=$id; [ -n "$key" ] && entry="$id:$key"
    case "$seen" in *" $entry "*) continue ;; esac
    seen="$seen$entry "; json_str_v je "$entry"; out="$out${out:+,}\"$je\""
  done <<<"$REC_LINES"
  printf '{"doctor":{"ignoreFindings":[%s]}}\n' "$out"
}

print_output() {
  local repo summary line joined=""
  summary="{\"critical\":$N_CRIT,\"warning\":$N_WARN,\"info\":$N_INFO,\"ok\":$N_OK,\"skipped\":$N_SKIP}"
  local jr js jm jd
  json_str_v jr "${REPO_ROOT:-}"; json_str_v js "${SLUG:-}"
  json_str_v jm "${MAIN:-}"; json_str_v jd "${DEVELOP:-}"
  local jl jn
  json_str_v jl "${LATEST_TAG:-}"; json_str_v jn "${NEXT_HOTFIX:-}"
  repo="{\"root\":\"$jr\",\"github\":\"$js\",\"main\":\"$jm\",\"develop\":\"$jd\",\"mergeMode\":{\"configured\":\"$MERGE_MODE\",\"resolved\":{\"main\":\"${RESOLVED_MAIN_MODE:-unknown}\",\"develop\":\"${RESOLVED_DEV_MODE:-unknown}\"}}"
  repo="$repo,\"versions\":{\"scheme\":\"${VERSION_SCHEME:-semver}\",\"latestTag\":\"$jl\",\"nextHotfix\":\"$jn\"}}"
  case "$FORMAT" in
    text) render_text; return ;;
    markdown) render_markdown; return ;;
    sarif) render_sarif; return ;;
    baseline) render_baseline; return ;;
  esac
  if [ "$FORMAT" = jsonl ]; then
    [ -n "$FINDINGS" ] && printf '%s\n' "$FINDINGS"
    printf '{"gitflowDoctor":"%s","repo":%s,"summary":%s}\n' "$DOCTOR_VERSION" "$repo" "$summary"
  else
    while IFS= read -r line; do
      [ -z "$line" ] && continue
      joined="$joined${joined:+,}$line"
    done <<<"$FINDINGS"
    printf '{"gitflowDoctor":"%s","repo":%s,"summary":%s,"findings":[%s]}\n' "$DOCTOR_VERSION" "$repo" "$summary" "$joined"
  fi
}

finish_exit() {
  print_output
  [ "$FORMAT" = baseline ] && exit 0 # a baseline is data, not a verdict
  case "$WORST" in 3) exit 2 ;; 2) exit 1 ;; *) exit 0 ;; esac
}

template_v() { # varname subject branch tag version -> placeholders substituted
  local __tp_s=$2 __tp_b='{branch}' __tp_t='{tag}' __tp_v='{version}' __tp_d="into {develop}" __tp_m="into {main}"
  [ -n "$3" ] && __tp_s=${__tp_s//"$3"/$__tp_b}
  [ -n "$4" ] && __tp_s=${__tp_s//"$4"/$__tp_t}
  [ -n "$5" ] && __tp_s=${__tp_s//"$5"/$__tp_v}
  [ -n "$DEVELOP" ] && __tp_s=${__tp_s//"into $DEVELOP"/$__tp_d}
  [ -n "$MAIN" ] && __tp_s=${__tp_s//"into $MAIN"/$__tp_m}
  printf -v "$1" '%s' "$__tp_s"
}

distinct_count_v() { # varname newline-list -> number of distinct lines (empty lines count too)
  local __dc_v=$1 __dc_l __dc_seen="$NL" __dc_n=0
  while IFS= read -r __dc_l; do
    case "$__dc_seen" in *"$NL$__dc_l$NL"*) continue ;; esac
    __dc_seen="$__dc_seen$__dc_l$NL"; __dc_n=$((__dc_n + 1))
  done <<<"$2"
  printf -v "$__dc_v" '%s' "$__dc_n"
}

# ===========================================================================
# WORKSPACE MODE — several repos released in lockstep (read-only). Runs before
# the repo bootstrap: the workspace file usually lives OUTSIDE any repo.
# ===========================================================================
WS_ITEM_RE='^[[:space:],]*("([^"]*)"|\{([^}]*)\})'
WS_PATH_RE='"path"[[:space:]]*:[[:space:]]*"([^"]*)"'
WS_OPT_RE='"optional"[[:space:]]*:[[:space:]]*true'
WS_POLICY_RE='"pushPolicy"[[:space:]]*:[[:space:]]*"([^"]*)"'
WS_SUMMARY_RE='"summary":(\{[^}]*\})'
WS_MAIN_RE='"main":"([^"]*)","develop"'
WS_LATEST_RE='"latestTag":"([^"]*)"'
WS_CRIT_RE='"critical":([0-9]+)'

in_repo() { # dir cmd... (subshell: the caller's cwd never changes)
  (cd "$1" || exit 1; shift; "$@")
}

ws_entries_v() { # varname workspace-file -> lines "optional<US>path"; also sets WS_POLICY
  local __we_v=$1 __we_all="" __we_l __we_arr __we_item __we_obj __we_p __we_opt __we_out=""
  while IFS= read -r __we_l || [ -n "$__we_l" ]; do __we_all="$__we_all ${__we_l%$'\r'}"; done <"$2"
  WS_POLICY=""
  [[ $__we_all =~ $WS_POLICY_RE ]] && WS_POLICY=${BASH_REMATCH[1]}
  case "$__we_all" in *'"repos"'*) : ;; *) die_usage "--workspace: no \"repos\" array in $2" ;; esac
  __we_arr=${__we_all#*'"repos"'}; __we_arr=${__we_arr#*[}; __we_arr=${__we_arr%%]*}
  while [[ $__we_arr =~ $WS_ITEM_RE ]]; do
    __we_item=${BASH_REMATCH[0]}; __we_p=${BASH_REMATCH[2]}; __we_obj=${BASH_REMATCH[3]}; __we_opt=false
    if [ -n "$__we_obj" ]; then
      __we_p=""
      [[ $__we_obj =~ $WS_PATH_RE ]] && __we_p=${BASH_REMATCH[1]}
      [[ $__we_obj =~ $WS_OPT_RE ]] && __we_opt=true
    fi
    __we_arr=${__we_arr:${#__we_item}}
    [ -n "$__we_p" ] && __we_out="$__we_out${__we_out:+$NL}$__we_opt$US$__we_p"
  done
  clear_v "$__we_v"
  [ -n "$__we_out" ] && printf -v "$__we_v" '%s' "$__we_out"
  return 0
}

ws_tag_facts() { # repo-dir main-name -> WT_EXISTS WT_TYPE WT_MSG WT_ONTIP
  local tf="" typ r obj peeled subj target tip=""
  WT_EXISTS=false; WT_TYPE=""; WT_MSG=""; WT_ONTIP=false
  capture tf git -C "$1" for-each-ref --format='%(objecttype)%09%(objectname)%09%(*objectname)%09%(contents:subject)' "refs/tags/$WS_TAG"
  [ -n "$tf" ] || return 0
  WT_EXISTS=true
  typ=${tf%%$'\t'*}; r=${tf#*$'\t'}; obj=${r%%$'\t'*}; r=${r#*$'\t'}; peeled=${r%%$'\t'*}; subj=${r#*$'\t'}
  target=$obj; WT_TYPE=lightweight
  if [ "$typ" = tag ]; then
    target=$peeled; WT_TYPE=annotated
    template_v WT_MSG "$subj" "" "$WS_TAG" "${WS_TAG#v}"
  fi
  if [ -n "$2" ]; then
    capture tip git -C "$1" rev-parse -q --verify "refs/remotes/origin/$2^{commit}"
    [ -z "$tip" ] && capture tip git -C "$1" rev-parse -q --verify "refs/heads/$2^{commit}"
  fi
  [ -n "$tip" ] && [ "$tip" = "$target" ] && WT_ONTIP=true
  return 0
}

ws_branch_json_v() { # varname repo-dir self -> ,"branch":{...}[,"probe":{...}]
  local __wb_v=$1 bl="" jb kind="" ver="" pr="" pj=null
  capture bl git -C "$2" for-each-ref --format='%(refname)' "refs/heads/$PROBE_BRANCH" "refs/remotes/origin/$PROBE_BRANCH"
  json_str_v jb "$PROBE_BRANCH"
  if [ -z "$bl" ]; then
    printf -v "$__wb_v" ',"branch":{"name":"%s","present":false,"skipped":"no branch"}' "$jb"
    return 0
  fi
  case "$PROBE_BRANCH" in
    "$RELEASE_PREFIX"*) kind=finish-release; ver=${PROBE_BRANCH#"$RELEASE_PREFIX"} ;;
    "$HOTFIX_PREFIX"*) kind=finish-hotfix; ver=${PROBE_BRANCH#"$HOTFIX_PREFIX"} ;;
    "$FEATURE_PREFIX"*) kind=finish-feature ;;
  esac
  if [ -n "$ver" ]; then
    # shellcheck disable=SC2086 # WS_PASS is a flag list, split on purpose
    capture pr in_repo "$2" bash "$3" --probe "$kind" --branch "$PROBE_BRANCH" --version "$ver" $WS_PASS
  elif [ -n "$kind" ]; then
    # shellcheck disable=SC2086
    capture pr in_repo "$2" bash "$3" --probe "$kind" --branch "$PROBE_BRANCH" $WS_PASS
  fi
  [ -n "$pr" ] && pj=$pr
  printf -v "$__wb_v" ',"branch":{"name":"%s","present":true},"probe":%s' "$jb" "$pj"
}

run_workspace() {
  local file=$WORKSPACE self=${BASH_SOURCE[0]} dir entries="" opt p rp jp robj repos="" dj summ rmain lt crit
  local status
  local ws_crit=0 bj types="" msgs="" rows="" missing=0 offtip=0 have_tag=0 jt jm reasons="" n line joined=""
  [ -f "$file" ] || die_usage "--workspace: file not found: $file"
  case "$self" in /*|[A-Za-z]:*) : ;; *) self="$PWD/$self" ;; esac
  dir=${file%/*}; [ "$dir" = "$file" ] && dir=.
  WS_PASS="--now $NOW"
  if [ "$OFFLINE" = 1 ]; then WS_PASS="$WS_PASS --offline"; elif [ "$DO_FETCH" = 0 ]; then WS_PASS="$WS_PASS --no-fetch"; fi
  ws_entries_v entries "$file"
  json_str_v jt "$WS_TAG"
  while IFS="$US" read -r opt p; do
    [ -z "$p" ] && continue
    rp=$p
    case "$p" in /*|[A-Za-z]:*) : ;; *) rp="$dir/$p" ;; esac
    json_str_v jp "$p"
    if [ ! -e "$rp/.git" ]; then
      repos="$repos${repos:+,}{\"path\":\"$jp\",\"optional\":$opt,\"status\":\"missing\"}"
      if [ "$opt" = false ]; then
        json_arr_v FIX "clone it at $rp, or mark it \"optional\": true in $file"
        fail_check workspace-repo-missing critical "required repo $p not found at $rp" "\"path\":\"$jp\"" "$FIX" workspace-repo-missing high "$p"
      fi
      continue
    fi
    dj=""
    # shellcheck disable=SC2086
    capture dj in_repo "$rp" bash "$self" --format json $WS_PASS
    summ="{}"; rmain=""; lt=""; crit=0
    [[ $dj =~ $WS_SUMMARY_RE ]] && summ=${BASH_REMATCH[1]}
    [[ $dj =~ $WS_MAIN_RE ]] && rmain=${BASH_REMATCH[1]}
    [[ $dj =~ $WS_LATEST_RE ]] && lt=${BASH_REMATCH[1]}
    [[ $summ =~ $WS_CRIT_RE ]] && crit=${BASH_REMATCH[1]}
    [ "$crit" -gt 0 ] && ws_crit=1
    status=ok; [ -z "$dj" ] && status=error
    robj="{\"path\":\"$jp\",\"optional\":$opt,\"status\":\"$status\",\"summary\":$summ,\"main\":\"$rmain\",\"latestTag\":\"$lt\""
    if [ -n "$PROBE_BRANCH" ]; then ws_branch_json_v bj "$rp" "$self"; robj="$robj$bj"; fi
    if [ -n "$WS_TAG" ]; then
      ws_tag_facts "$rp" "$rmain"
      if [ "$WT_EXISTS" = true ]; then
        have_tag=1
        json_str_v jm "$WT_MSG"
        robj="$robj,\"tag\":{\"name\":\"$jt\",\"type\":\"$WT_TYPE\",\"message\":\"$jm\",\"onMainTip\":$WT_ONTIP}"
        types="$types${types:+$NL}$WT_TYPE"
        [ "$WT_TYPE" = annotated ] && msgs="$msgs${msgs:+$NL}$WT_MSG" # lightweight tags carry no message
        [ "$WT_ONTIP" = false ] && offtip=1
        rows="$rows${rows:+,}{\"path\":\"$jp\",\"type\":\"$WT_TYPE\",\"message\":\"$jm\",\"onMainTip\":$WT_ONTIP}"
      else
        robj="$robj,\"tag\":{\"name\":\"$jt\",\"exists\":false}"
        [ "$opt" = false ] && missing=1
        rows="$rows${rows:+,}{\"path\":\"$jp\",\"exists\":false}"
      fi
    fi
    repos="$repos${repos:+,}$robj}"
  done <<<"$entries"

  if [ "$have_tag" = 1 ]; then
    distinct_count_v n "$types"; [ "$n" -gt 1 ] && reasons="$reasons${reasons:+,}\"type\""
    distinct_count_v n "$msgs"; [ "$n" -gt 1 ] && reasons="$reasons${reasons:+,}\"message\""
    [ "$missing" = 1 ] && reasons="$reasons${reasons:+,}\"missing\""
    [ "$offtip" = 1 ] && reasons="$reasons${reasons:+,}\"not-on-main-tip\""
    if [ -n "$reasons" ]; then
      json_arr_v FIX "compare: git -C <repo> for-each-ref --format='%(objecttype) %(*objectname) %(contents:subject)' refs/tags/$WS_TAG" "recreate the odd one out only after the team agrees (tags are shared history)"
      fail_check tag-convention-drift warning "tag $WS_TAG differs across the workspace" \
        "\"tag\":\"$jt\",\"reasons\":[$reasons],\"repos\":[$rows]" "$FIX" tag-convention-drift high "$WS_TAG"
    fi
  fi
  while IFS= read -r line; do [ -n "$line" ] && joined="$joined${joined:+,}$line"; done <<<"$FINDINGS"
  local ready=true jf jpol
  { [ "$WORST" -ge 2 ] || [ "$ws_crit" = 1 ]; } && ready=false
  json_str_v jf "$file"; json_str_v jpol "$WS_POLICY"
  printf '{"gitflowDoctor":"%s","workspace":{"file":"%s","pushPolicy":"%s","ready":%s,"repos":[%s],"findings":[%s]}}\n' \
    "$DOCTOR_VERSION" "$jf" "$jpol" "$ready" "$repos" "$joined"
  [ "$ws_crit" = 1 ] && [ "$WORST" -lt 3 ] && WORST=3
  case "$WORST" in 3) exit 2 ;; 2) exit 1 ;; *) exit 0 ;; esac
}
[ -n "$WORKSPACE" ] && run_workspace

# ---------------------------------------------------------------------------
# Repo bootstrap: one rev-parse batch answers repo/root/shallow at once
# ---------------------------------------------------------------------------
BOOT=""
capture_all BOOT git rev-parse --is-inside-work-tree --show-toplevel --is-shallow-repository
if [ -z "$BOOT" ]; then
  local_cwd=$PWD
  json_str_v jcwd "$local_cwd"
  json_arr_v FIXC "git init" "cd <your-repo>"
  # shellcheck disable=SC2154 # jcwd/FIXC are assigned via printf -v inside the helpers
  fail_check env-not-a-repo critical "not inside a git work tree" "\"cwd\":\"$jcwd\"" "$FIXC" env-not-a-repo
  finish_exit
fi
{ IFS= read -r _in_tree; IFS= read -r REPO_ROOT; IFS= read -r _shallow; } <<<"$BOOT"
SHALLOW=0; [ "$_shallow" = true ] && SHALLOW=1

# .gitflow.json fallback for standalone runs (hooks, CI action, brew users): a
# zero-spawn scan of the scalar keys the doctor understands; the agent passes
# everything as flags, which always win. Several keys may share one line.
CONFIG_FILE="$REPO_ROOT/.gitflow.json"
CFG_KEY_RE='"(main|develop|tagPrefix|mergeMode|staleDays|maxConcurrent|changelog|file|enabled|githubRelease|signedTags|tap|formula|scheme|hotfixPattern)"[[:space:]]*:[[:space:]]*("([^"]*)"|[0-9]+|true|false|\{)'
if [ -f "$CONFIG_FILE" ]; then
  CFG_CL_BLOCK=0; CFG_CL_FILE=""; CFG_CL_ENABLED=true
  while IFS= read -r line || [ -n "$line" ]; do
    while [[ $line =~ $CFG_KEY_RE ]]; do
      key=${BASH_REMATCH[1]}; val=${BASH_REMATCH[2]}
      case "$val" in \"*) val=${BASH_REMATCH[3]} ;; esac
      line=${line#*"${BASH_REMATCH[0]}"}
      case "$key" in
        main) [ -z "$MAIN" ] && MAIN=$val ;;
        develop) [ -z "$DEVELOP" ] && DEVELOP=$val ;;
        tagPrefix) [ "$TAG_PREFIX" = "__UNSET__" ] && TAG_PREFIX=$val ;;
        mergeMode) [ "$MERGE_MODE" = auto ] && MERGE_MODE=$val ;;
        staleDays) [ -z "$STALE_DAYS" ] && STALE_DAYS=$val ;;
        maxConcurrent) [ -z "$MAX_RELEASES" ] && MAX_RELEASES=$val ;;
        changelog) [ "$val" = "{" ] && CFG_CL_BLOCK=1 ;; # the block, not backmerge.conflictPolicy.changelog
        file) CFG_CL_FILE=$val ;;
        enabled) CFG_CL_ENABLED=$val ;;
        githubRelease) [ "$val" = false ] && GITHUB_RELEASE=0 ;;
        signedTags) [ "$val" = true ] && REQUIRE_SIGNED_TAGS=1 ;;
        tap) [ -z "$HOMEBREW_TAP" ] && HOMEBREW_TAP=$val ;;
        formula) [ -z "$HOMEBREW_FORMULA" ] && HOMEBREW_FORMULA=$val ;;
        scheme) [ -z "$VERSION_SCHEME" ] && VERSION_SCHEME=$val ;;
        hotfixPattern) [ -z "$HOTFIX_PATTERN" ] && HOTFIX_PATTERN=$val ;;
      esac
    done
  done <"$CONFIG_FILE"
  # changelog block present and not disabled -> its file (default CHANGELOG.md)
  if [ -z "$CHANGELOG_FILE" ] && [ "$CFG_CL_BLOCK" = 1 ] && [ "$CFG_CL_ENABLED" != false ]; then
    CHANGELOG_FILE=${CFG_CL_FILE:-CHANGELOG.md}
  fi
fi
[ "$TAG_PREFIX" = "__UNSET__" ] && TAG_PREFIX=v
[ -z "$DEVELOP" ] && DEVELOP=develop
[ -z "$STALE_DAYS" ] && STALE_DAYS=30
[ -z "$SCAN_DEPTH" ] && SCAN_DEPTH=200
[ -z "$MAX_RELEASES" ] && MAX_RELEASES=1
[ "$ALLOW_PRERELEASE" = 1 ] && RELEASE_NAME_RE=$RELEASE_NAME_PRE_RE
case "$VERSION_SCHEME" in
  ''|semver) VERSION_SCHEME=semver ;;
  suffix-counter)
    # {base}<infix>{n}: the infix must turn X.Y.Z into a SemVer prerelease
    # (leading '-') and must not end in a digit, or N would be ambiguous
    [ -z "$HOTFIX_PATTERN" ] && HOTFIX_PATTERN='{base}-hotfix.{n}'
    case "$HOTFIX_PATTERN" in
      "{base}"*"{n}") HOTFIX_INFIX=${HOTFIX_PATTERN#"{base}"}; HOTFIX_INFIX=${HOTFIX_INFIX%"{n}"} ;;
    esac
    [[ $HOTFIX_INFIX =~ ^-[0-9A-Za-z.-]*[A-Za-z.-]$ ]] \
      || die_usage "--hotfix-pattern must look like {base}-hotfix.{n} (got '$HOTFIX_PATTERN')" ;;
  *) die_usage "versionScheme.scheme must be semver or suffix-counter (got '$VERSION_SCHEME')" ;;
esac

# git version gate for merge-tree (needs >= 2.38); parsed without spawning sed
GITV=""
capture GITV git version
GITV=${GITV#git version }
V_MAJ=${GITV%%.*}; V_REST=${GITV#*.}; V_MIN=${V_REST%%.*}
case "$V_MAJ$V_MIN" in *[!0-9]*) V_MAJ=0; V_MIN=0 ;; esac
MERGETREE_OK=0
if [ "${V_MAJ:-0}" -gt 2 ] || { [ "${V_MAJ:-0}" -eq 2 ] && [ "${V_MIN:-0}" -ge 38 ]; }; then MERGETREE_OK=1; fi

# origin / GitHub resolution
ORIGIN_URL=""
capture ORIGIN_URL git remote get-url origin
SLUG=""
if [ -n "$ASSUME_GITHUB" ]; then
  SLUG=$ASSUME_GITHUB
elif [ -n "$ORIGIN_URL" ]; then
  case "$ORIGIN_URL" in
    *github.com[:/]*)
      SLUG=${ORIGIN_URL##*github.com[:/]}
      SLUG=${SLUG%.git}
      case "$SLUG" in */*/*|*/) SLUG="" ;; esac ;;
  esac
fi

remote_is_local() {
  case "$ORIGIN_URL" in
    "") return 1 ;;
    file://*) return 0 ;;
    http://*|https://*|ssh://*|git://*) return 1 ;;
    *) [ -e "$ORIGIN_URL" ] && return 0
       case "$ORIGIN_URL" in *:*) return 1 ;; *) return 0 ;; esac ;;
  esac
}
LS_REMOTE_OK=1
if [ "$OFFLINE" = 1 ] && ! remote_is_local; then LS_REMOTE_OK=0; fi
[ -z "$ORIGIN_URL" ] && LS_REMOTE_OK=0

GH_MODE=0
GH_STATE="off"
if [ "$OFFLINE" = 1 ]; then GH_STATE="offline"
elif [ -z "$SLUG" ]; then GH_STATE="not-github-remote"
elif ! command -v gh >/dev/null 2>&1; then GH_STATE="gh-missing"
elif ! gh auth status >/dev/null 2>&1; then GH_STATE="gh-unauthenticated"
else GH_MODE=1; GH_STATE="ok"; fi

# fetch — the one permitted cache mutation
FETCH_FAILED=0
if [ "$DO_FETCH" = 1 ] && [ -n "$ORIGIN_URL" ]; then
  git fetch origin --prune --tags --quiet 2>/dev/null || FETCH_FAILED=1
fi

# ---------------------------------------------------------------------------
# THE REF SNAPSHOT — one for-each-ref call, then pure-bash lookups only.
# Line format: <refname> <sha> <objecttype> <committerdate:unix> [<peeled>]
# ---------------------------------------------------------------------------
# Pipe-delimited: empty fields (tag objects have no committerdate, plain refs
# have no peeled sha) must not shift columns the way collapsed spaces would.
SNAP=""
capture_all SNAP git for-each-ref \
  --format='%(refname)|%(objectname)|%(objecttype)|%(committerdate:unix)|%(*objectname)' \
  refs/heads refs/remotes/origin refs/tags

LOCAL_LINES=""    # "<name> <sha> <cdate>"
REMOTE_LINES=""   # "<name> <sha> <cdate>" (origin/ stripped)
TAG_LINES=""      # "<name> <commit-sha> <objecttype>"
TAGGED_SHAS=" "   # " sha1 sha2 " membership string
while IFS='|' read -r rn sha typ cdate peeled; do
  [ -z "$rn" ] && continue
  case "$rn" in
    refs/heads/*)
      LOCAL_LINES="$LOCAL_LINES${LOCAL_LINES:+$NL}${rn#refs/heads/} $sha $cdate" ;;
    refs/remotes/origin/HEAD) : ;;
    refs/remotes/origin/*)
      REMOTE_LINES="$REMOTE_LINES${REMOTE_LINES:+$NL}${rn#refs/remotes/origin/} $sha $cdate" ;;
    refs/tags/*)
      tcommit=$sha
      [ "$typ" = tag ] && [ -n "$peeled" ] && tcommit=$peeled
      TAG_LINES="$TAG_LINES${TAG_LINES:+$NL}${rn#refs/tags/} $tcommit $typ"
      TAGGED_SHAS="$TAGGED_SHAS$tcommit " ;;
  esac
done <<<"$SNAP"

lookup_line() { # varname haystack key  -> line starting "key "
  # NOTE: internal names are __ll_-prefixed: bash locals are dynamically
  # scoped, so an unprefixed local would shadow the caller's target varname.
  local __ll_v=$1 __ll_line
  clear_v "$__ll_v"
  while IFS= read -r __ll_line; do
    case "$__ll_line" in "$3 "*) printf -v "$__ll_v" '%s' "$__ll_line"; return 0 ;; esac
  done <<<"$2"
  return 1
}

local_branch_exists() { lookup_line _ll "$LOCAL_LINES" "$1"; }
remote_branch_exists() { lookup_line _rl "$REMOTE_LINES" "$1"; }
tag_exists() { lookup_line _tl "$TAG_LINES" "$1"; }
tag_commit_v() { # varname tagname
  local L=""
  if lookup_line L "$TAG_LINES" "$2"; then
    L=${L#* }
    printf -v "$1" '%s' "${L%% *}"
  else
    clear_v "$1"
  fi
}
sha_is_tagged() { case "$TAGGED_SHAS" in *" $1 "*) return 0 ;; esac; return 1; }

branch_ref_v() { # varname shortname -> refs/remotes/origin/N or refs/heads/N or ""
  if remote_branch_exists "$2"; then printf -v "$1" 'refs/remotes/origin/%s' "$2"
  elif local_branch_exists "$2"; then printf -v "$1" 'refs/heads/%s' "$2"
  else clear_v "$1"; fi
}

list_branches_v() { # varname glob -> newline list of unique short names (local+remote)
  local __v=$1 pat=$2 line name out="" seen=" "
  clear_v "$__v"
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    name=${line%% *}
    # shellcheck disable=SC2254
    case "$name" in
      $pat)
        case "$seen" in *" $name "*) : ;; *) out="$out${out:+$NL}$name"; seen="$seen$name " ;; esac ;;
    esac
  done <<<"$LOCAL_LINES$NL$REMOTE_LINES"
  printf -v "$__v" '%s' "$out"
}

# main default: prefer explicit config, else master if it exists, else main
if [ -z "$MAIN" ]; then
  if local_branch_exists master || remote_branch_exists master; then MAIN=master; else MAIN=main; fi
fi

branch_ref_v R_MAIN "$MAIN"
branch_ref_v R_DEV "$DEVELOP"
CURRENT_BRANCH="-"
if any_enabled detached-head || [ -n "$PROBE" ]; then
  CURRENT_BRANCH=""
  capture CURRENT_BRANCH git symbolic-ref -q --short HEAD
fi

is_semver_tag() { # tag name including prefix
  local s=$1
  case "$s" in "$TAG_PREFIX"*) : ;; *) return 1 ;; esac
  s=${s#"$TAG_PREFIX"}
  [[ $s =~ $SEMVER_RE ]]
}

# ---------------------------------------------------------------------------
# Version precedence, computed in bash: strict SemVer 2.0, plus the
# suffix-counter scheme where X.Y.Z<infix>N is a POST-release of X.Y.Z (after
# X.Y.Z, before X.Y.Z+1; N numeric). git's version sort is never trusted for
# this — `versionsort.suffix` in the user's config reorders prereleases.
# ---------------------------------------------------------------------------
VCMP=0
num_cmp() { # a b (decimal strings) -> VCMP
  if [ "$1" -lt "$2" ]; then VCMP=-1; elif [ "$1" -gt "$2" ]; then VCMP=1; else VCMP=0; fi
}
prerelease_cmp() { # a b (dot-separated identifiers) -> VCMP, SemVer rule 11
  local ra="$1." rb="$2." ia ib
  while :; do
    if [ -z "$ra" ] && [ -z "$rb" ]; then VCMP=0; return; fi
    [ -z "$ra" ] && { VCMP=-1; return; }
    [ -z "$rb" ] && { VCMP=1; return; }
    ia=${ra%%.*}; ra=${ra#*.}; ib=${rb%%.*}; rb=${rb#*.}
    if [[ $ia =~ ^[0-9]+$ ]]; then
      [[ $ib =~ ^[0-9]+$ ]] || { VCMP=-1; return; }
      num_cmp "$ia" "$ib"; [ "$VCMP" != 0 ] && return
    elif [[ $ib =~ ^[0-9]+$ ]]; then VCMP=1; return
    elif [[ $ia < $ib ]]; then VCMP=-1; return
    elif [[ $ia > $ib ]]; then VCMP=1; return
    fi
  done
}
counter_version_parts() { # version -> 0 + CV_BASE/CV_N when it is X.Y.Z<infix>N
  [ -n "$HOTFIX_INFIX" ] || return 1
  case "$1" in *"$HOTFIX_INFIX"*) : ;; *) return 1 ;; esac
  CV_BASE=${1%"$HOTFIX_INFIX"*}; CV_N=${1##*"$HOTFIX_INFIX"}
  [[ $CV_BASE =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] && [[ $CV_N =~ ^[0-9]+$ ]]
}
CV_BASE=""; CV_N=""
ver_parts() { # prefix version -> <prefix>Maj Min Pat Kind(-1 pre, 0 release, 1 post) Rest
  local __vp_s=${2%%+*} __vp_core __vp_rest="" __vp_kind=0 __vp_a __vp_b __vp_c
  case "$__vp_s" in
    *-*) __vp_core=${__vp_s%%-*}; __vp_rest=${__vp_s#*-}; __vp_kind=-1 ;;
    *) __vp_core=$__vp_s ;;
  esac
  if counter_version_parts "$__vp_s"; then __vp_core=$CV_BASE; __vp_rest=$CV_N; __vp_kind=1; fi
  IFS=. read -r __vp_a __vp_b __vp_c <<<"$__vp_core"
  printf -v "${1}Maj" '%s' "${__vp_a:-0}"
  printf -v "${1}Min" '%s' "${__vp_b:-0}"
  printf -v "${1}Pat" '%s' "${__vp_c:-0}"
  printf -v "${1}Kind" '%s' "$__vp_kind"
  printf -v "${1}Rest" '%s' "${__vp_rest:-0}"
}
version_cmp() { # a b (bare versions, no tag prefix) -> VCMP -1/0/1
  ver_parts _va "$1"; ver_parts _vb "$2"
  num_cmp "$_vaMaj" "$_vbMaj"; [ "$VCMP" != 0 ] && return
  num_cmp "$_vaMin" "$_vbMin"; [ "$VCMP" != 0 ] && return
  num_cmp "$_vaPat" "$_vbPat"; [ "$VCMP" != 0 ] && return
  num_cmp "$_vaKind" "$_vbKind"; [ "$VCMP" != 0 ] && return
  case "$_vaKind" in
    -1) prerelease_cmp "$_vaRest" "$_vbRest" ;;
    1) num_cmp "$_vaRest" "$_vbRest" ;;
    *) VCMP=0 ;;
  esac
}
version_le() { version_cmp "$1" "$2"; [ "$VCMP" != 1 ]; }

# merged-into-main tag list (one git call) -> latest/oldest semver + membership
MERGED_TAGS=""
LATEST_TAG=""
OLDEST_TAG=""
if [ -n "$R_MAIN" ]; then
  capture_all MERGED_TAGS git tag --list --merged "$R_MAIN" --sort=-version:refname
  latest_v=""; oldest_v=""
  while IFS= read -r t; do
    [ -z "$t" ] && continue
    is_semver_tag "$t" || continue
    v=${t#"$TAG_PREFIX"}
    if [ -z "$LATEST_TAG" ]; then
      LATEST_TAG=$t; OLDEST_TAG=$t; latest_v=$v; oldest_v=$v
      continue
    fi
    version_cmp "$v" "$latest_v"; [ "$VCMP" = 1 ] && { LATEST_TAG=$t; latest_v=$v; }
    version_cmp "$v" "$oldest_v"; [ "$VCMP" = -1 ] && { OLDEST_TAG=$t; oldest_v=$v; }
  done <<<"$MERGED_TAGS"
fi

# next hotfix version: above the latest tag AND above every open hotfix branch
# on the same line (their numbers are taken even before they are tagged)
NEXT_HOTFIX=""
[ -n "$LATEST_TAG" ] && ver_parts _nh "${LATEST_TAG#"$TAG_PREFIX"}"
# a prerelease as the latest tag means X.Y.Z itself never shipped: there is
# nothing to hotfix yet, so no suggestion (the agent asks the user)
if [ -n "$LATEST_TAG" ] && [ "$_nhKind" != -1 ]; then
  nh_hot=""; list_branches_v nh_hot "${HOTFIX_PREFIX}*"
  if [ "$VERSION_SCHEME" = suffix-counter ]; then
    nh_base="$_nhMaj.$_nhMin.$_nhPat"; nh_n=0
    [ "$_nhKind" = 1 ] && nh_n=$_nhRest
    while IFS= read -r br; do
      counter_version_parts "${br#"$HOTFIX_PREFIX"}" || continue
      [ "$CV_BASE" = "$nh_base" ] && [ "$CV_N" -gt "$nh_n" ] && nh_n=$CV_N
    done <<<"$nh_hot"
    NEXT_HOTFIX="$nh_base$HOTFIX_INFIX$((10#$nh_n + 1))"
  else
    nh_p=$_nhPat
    while IFS= read -r br; do
      v=${br#"$HOTFIX_PREFIX"}
      [[ $v =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]] || continue
      [ "${BASH_REMATCH[1]}.${BASH_REMATCH[2]}" = "$_nhMaj.$_nhMin" ] && [ "${BASH_REMATCH[3]}" -gt "$nh_p" ] && nh_p=${BASH_REMATCH[3]}
    done <<<"$nh_hot"
    NEXT_HOTFIX="$_nhMaj.$_nhMin.$((10#$nh_p + 1))"
  fi
fi
tag_on_main() { # tag name — membership in the merged-into-main list
  local t
  while IFS= read -r t; do [ "$t" = "$1" ] && return 0; done <<<"$MERGED_TAGS"
  return 1
}

# develop tree oid, cached for content-equivalence checks
DEV_TREE=""
if [ -n "$R_DEV" ] && [ "$MERGETREE_OK" = 1 ] && { [ -n "$PROBE" ] || any_enabled missing-back-merge back-merge-content-only branch-stale-merged; }; then
  capture DEV_TREE git rev-parse "$R_DEV^{tree}"
fi

content_absorbed_into_dev() { # ref: merging ref into develop changes nothing
  [ "$MERGETREE_OK" = 1 ] || return 1
  [ -n "$DEV_TREE" ] || return 1
  local tree=""
  capture tree git merge-tree --write-tree --no-messages "$R_DEV" "$1"
  [ -n "$tree" ] && [ "$tree" = "$DEV_TREE" ]
}

content_absorbed_into() { # base_ref other_ref (generic; 2 spawns)
  [ "$MERGETREE_OK" = 1 ] || return 1
  local tree="" base=""
  capture tree git merge-tree --write-tree --no-messages "$1" "$2"
  [ -n "$tree" ] || return 1
  capture base git rev-parse "$1^{tree}"
  [ "$tree" = "$base" ]
}

release_is_finished() { # release branch short name -> 0 when that version already shipped
  local __rf_ver="" __rf_tag="" __rf_ref=""
  case "$1" in "$RELEASE_PREFIX"*) __rf_ver=${1#"$RELEASE_PREFIX"} ;; *) return 1 ;; esac
  __rf_tag="${TAG_PREFIX}${__rf_ver}"
  tag_exists "$__rf_tag" || return 1
  [ -n "$R_MAIN" ] || return 1
  branch_ref_v __rf_ref "$1"
  [ -n "$__rf_ref" ] || return 1
  git merge-base --is-ancestor "$__rf_ref" "$R_MAIN" 2>/dev/null && return 0
  content_absorbed_into "$R_MAIN" "$__rf_ref"
}

open_releases_v() { # varname newline-list -> entries that have NOT shipped yet
  local __or_v=$1 __or_br __or_out=""
  while IFS= read -r __or_br; do
    [ -z "$__or_br" ] && continue
    release_is_finished "$__or_br" && continue
    __or_out="$__or_out${__or_out:+$NL}$__or_br"
  done <<<"$2"
  printf -v "$__or_v" '%s' "$__or_out"
}

conflicts_predicted() { # ref_a ref_b
  [ "$MERGETREE_OK" = 1 ] || return 1
  ! git merge-tree --write-tree --no-messages "$1" "$2" >/dev/null 2>&1
}

merge_conflicts_v() { # varname ref_a ref_b -> newline list of paths the merge would conflict on
  # One merge-tree call; output is the tree oid, then one conflicted path per
  # line. Empty when clean, when merge-tree is unavailable, or on error.
  local __mc_v=$1 __mc_out="" __mc_line __mc_acc="" __mc_first=1
  clear_v "$__mc_v"
  [ "$MERGETREE_OK" = 1 ] || return 0
  capture_all __mc_out git merge-tree --write-tree --name-only --no-messages "$2" "$3"
  while IFS= read -r __mc_line; do
    if [ "$__mc_first" = 1 ]; then __mc_first=0; continue; fi
    [ -z "$__mc_line" ] && continue
    case "$NL$__mc_acc$NL" in *"$NL$__mc_line$NL"*) continue ;; esac
    __mc_acc="$__mc_acc${__mc_acc:+$NL}$__mc_line"
  done <<<"$__mc_out"
  [ -n "$__mc_acc" ] && printf -v "$__mc_v" '%s' "$__mc_acc"
  return 0
}

json_lines_v() { # varname newline-list -> JSON array of strings
  local __jl_v=$1 __jl_line __jl_e __jl_out=""
  while IFS= read -r __jl_line; do
    [ -z "$__jl_line" ] && continue
    json_str_v __jl_e "$__jl_line"
    __jl_out="$__jl_out${__jl_out:+,}\"$__jl_e\""
  done <<<"$2"
  printf -v "$__jl_v" '[%s]' "$__jl_out"
}

open_hotfixes_v() { # varname newline-list -> hotfix branches whose tag does not exist yet
  local __oh_v=$1 __oh_br __oh_out=""
  while IFS= read -r __oh_br; do
    [ -z "$__oh_br" ] && continue
    tag_exists "${TAG_PREFIX}${__oh_br#"$HOTFIX_PREFIX"}" && continue
    __oh_out="$__oh_out${__oh_out:+$NL}$__oh_br"
  done <<<"$2"
  clear_v "$__oh_v"
  [ -n "$__oh_out" ] && printf -v "$__oh_v" '%s' "$__oh_out"
  return 0
}

sort_by_version_v() { # varname newline-list-of-branches prefix -> same list, ascending version
  local __sv_v=$1 __sv_pfx=$3 __sv_br __sv_out="" __sv_rest __sv_x __sv_new __sv_done
  while IFS= read -r __sv_br; do
    [ -z "$__sv_br" ] && continue
    __sv_new=""; __sv_done=0; __sv_rest=$__sv_out
    while IFS= read -r __sv_x; do
      [ -z "$__sv_x" ] && continue
      if [ "$__sv_done" = 0 ]; then
        version_cmp "${__sv_br#"$__sv_pfx"}" "${__sv_x#"$__sv_pfx"}"
        if [ "$VCMP" = -1 ]; then __sv_new="$__sv_new${__sv_new:+$NL}$__sv_br"; __sv_done=1; fi
      fi
      __sv_new="$__sv_new${__sv_new:+$NL}$__sv_x"
    done <<<"$__sv_rest"
    [ "$__sv_done" = 0 ] && __sv_new="$__sv_new${__sv_new:+$NL}$__sv_br"
    __sv_out=$__sv_new
  done <<<"$2"
  clear_v "$__sv_v"
  [ -n "$__sv_out" ] && printf -v "$__sv_v" '%s' "$__sv_out"
  return 0
}

extract_version_v() { # varname ref path pattern — ERE with capture group 1, one process
  local __v=$1 ref=$2 path=$3 pat=$4 content="" line
  clear_v "$__v"
  capture_all content git show "$ref:$path"
  while IFS= read -r line; do
    if [[ $line =~ $pat ]]; then
      printf -v "$__v" '%s' "${BASH_REMATCH[1]}"
      return 0
    fi
  done <<<"$content"
  return 1
}

vf_path_v() { # varname index(0-based)
  local i=0 line
  clear_v "$1"
  while IFS= read -r line; do [ "$i" = "$2" ] && { printf -v "$1" '%s' "$line"; return; }; i=$((i + 1)); done <<<"$VF_PATHS"
}
vf_pattern_v() {
  local i=0 line
  clear_v "$1"
  while IFS= read -r line; do [ "$i" = "$2" ] && { printf -v "$1" '%s' "$line"; return; }; i=$((i + 1)); done <<<"$VF_PATTERNS"
}

# gh protection cache (feeds repo.mergeMode.resolved + gh checks)
PROT_MAIN=""; PROT_DEV=""
if [ "$GH_MODE" = 1 ]; then
  capture PROT_MAIN gh api "repos/$SLUG/branches/$MAIN" --jq .protected
  capture PROT_DEV gh api "repos/$SLUG/branches/$DEVELOP" --jq .protected
fi
resolve_mode_v() { # varname protected-value
  case "$MERGE_MODE" in
    pr|local) printf -v "$1" '%s' "$MERGE_MODE" ;;
    *) case "$2" in
         true) printf -v "$1" 'pr' ;;
         false) printf -v "$1" 'local' ;;
         *) printf -v "$1" 'unknown' ;;
       esac ;;
  esac
}
resolve_mode_v RESOLVED_MAIN_MODE "$PROT_MAIN"
resolve_mode_v RESOLVED_DEV_MODE "$PROT_DEV"

homebrew_configured() { [ -n "$HOMEBREW_TAP" ] && [ -n "$HOMEBREW_FORMULA" ]; }
tap_formula_v() { # varname -> raw formula from the tap's default branch ("" on failure); one gh call
  capture_all "$1" gh api -H "Accept: application/vnd.github.raw" "repos/$HOMEBREW_TAP/contents/$HOMEBREW_FORMULA"
}
formula_has_tag() { # formula-content tag -> the url line points at that tag's tarball
  case "$1" in *"/tags/$2.tar.gz"*) return 0 ;; esac
  return 1
}
formula_tag_v() { # varname formula-content -> the tag the url currently ships ("" if none)
  local __ft=$2
  case "$__ft" in
    *"/tags/"*".tar.gz"*) __ft=${__ft##*/tags/}; printf -v "$1" '%s' "${__ft%%.tar.gz*}" ;;
    *) clear_v "$1" ;;
  esac
}

# ===========================================================================
# PROBE MODE
# ===========================================================================
PROBE_STEPS=""
PROBE_WARNINGS=""
add_step() { # name done extra_fragment
  local extra=${3:-}
  PROBE_STEPS="$PROBE_STEPS${PROBE_STEPS:+,}{\"step\":\"$1\",\"done\":$2${extra:+,$extra}}"
}
add_probe_warning() {
  local jw; json_str_v jw "$1"
  PROBE_WARNINGS="$PROBE_WARNINGS${PROBE_WARNINGS:+,}\"$jw\""
}

MERGED=false; MERGE_SHA=""; MERGE_VIA=""
probe_merged_into() { # branch target_ref
  local branch=$1 target=$2 bref tip="" line=""
  MERGED=false; MERGE_SHA=""; MERGE_VIA=""
  branch_ref_v bref "$branch"
  if [ -n "$bref" ] && [ -n "$target" ] && git merge-base --is-ancestor "$bref" "$target" 2>/dev/null; then
    MERGED=true; MERGE_VIA="ancestry"
    tip=${bref#refs/remotes/origin/}; tip=${tip#refs/heads/}
    # find the merge commit whose parent list contains the branch tip
    local tipsha="" parents=""
    if remote_branch_exists "$tip"; then lookup_line parents "$REMOTE_LINES" "$tip"; else lookup_line parents "$LOCAL_LINES" "$tip"; fi
    parents=${parents#* }; tipsha=${parents%% *}
    capture_all parents git rev-list --first-parent --merges -n "$SCAN_DEPTH" "$target" --parents
    while IFS= read -r line; do
      case "$line" in *"$tipsha"*) MERGE_SHA=${line%% *}; break ;; esac
    done <<<"$parents"
    [ -z "$MERGE_SHA" ] && MERGE_SHA=$tipsha # fast-forward case
    return 0
  fi
  if [ "$GH_MODE" = 1 ]; then
    local tshort=${target##*/}
    capture line gh pr list --head "$branch" --base "$tshort" --state merged --json number,mergeCommit --jq '.[] | "\(.number) \(.mergeCommit.oid)"'
    if [ -n "$line" ]; then
      MERGED=true; MERGE_VIA="pr#${line%% *}"; MERGE_SHA=${line##* }
      return 0
    fi
  fi
  if [ -n "$bref" ] && [ -n "$target" ] && content_absorbed_into "$target" "$bref"; then
    MERGED=true; MERGE_VIA="content-equivalent"
    return 0
  fi
  return 1
}

PROBE_FORECAST=""
forecast_warning() { # conflict-list target-name
  [ -n "$1" ] || return 0
  local __fw_list=${1//$NL/, }
  add_probe_warning "conflicts predicted merging $PROBE_BRANCH into $2: $__fw_list — resolve on the branch before the finish (fix-recipes.md#flow-branch-behind-main)"
}

run_probe() {
  local tag="${TAG_PREFIX}${PROBE_VERSION}" bref jt jb fc_main="" fc_bm="" fc_dev="" jfm jfb jfd
  branch_ref_v bref "$PROBE_BRANCH"

  if [ "$PROBE" = finish-feature ]; then
    probe_merged_into "$PROBE_BRANCH" "$R_DEV" || :
    # branch deleted everywhere and no counter-evidence: the finish completed
    if [ "$MERGED" = false ] && [ -z "$bref" ]; then
      MERGED=true; MERGE_VIA="branch-gone"
    fi
    json_str_v jt "$MERGE_VIA"
    add_step merged-to-develop "$MERGED" "\"via\":\"$jt\""
    if [ "$MERGED" = false ] && [ -n "$bref" ]; then
      merge_conflicts_v fc_dev "$R_DEV" "$bref"
      forecast_warning "$fc_dev" "$DEVELOP"
    fi
    json_lines_v jfd "$fc_dev"
    PROBE_FORECAST="\"develop\":$jfd"
  else
    # version-bumped
    if [ "$VF_COUNT" -eq 0 ]; then
      add_step version-bumped true "\"detail\":\"no version files configured\""
    elif [ -z "$bref" ]; then
      add_step version-bumped true "\"detail\":\"branch gone (assumed merged)\""
    else
      local i=0 missing="" p pat got
      while [ "$i" -lt "$VF_COUNT" ]; do
        vf_path_v p "$i"; vf_pattern_v pat "$i"
        extract_version_v got "$bref" "$p" "$pat"
        [ "$got" != "$PROBE_VERSION" ] && missing="$missing${missing:+, }$p=$got"
        i=$((i + 1))
      done
      if [ -z "$missing" ]; then
        add_step version-bumped true "\"detail\":\"all version files at $PROBE_VERSION\""
      else
        json_str_v jt "$missing"
        add_step version-bumped false "\"detail\":\"$jt\""
      fi
    fi

    # merged-to-main
    probe_merged_into "$PROBE_BRANCH" "$R_MAIN" || :
    # fallback 1: the branch may be gone, but its release tag reached main
    if [ "$MERGED" = false ] && tag_exists "$tag"; then
      local tag_sha=""
      tag_commit_v tag_sha "$tag"
      if [ -n "$tag_sha" ] && git merge-base --is-ancestor "$tag_sha" "$R_MAIN" 2>/dev/null; then
        MERGED=true; MERGE_VIA="tag"; MERGE_SHA=$tag_sha
      fi
    fi
    # fallback 2: branch deleted everywhere — the finish completed
    if [ "$MERGED" = false ] && [ -z "$bref" ]; then
      MERGED=true; MERGE_VIA="branch-gone"
    fi
    local main_merge_sha=$MERGE_SHA
    json_str_v jt "$MERGE_VIA"
    add_step merged-to-main "$MERGED" "\"sha\":\"$MERGE_SHA\",\"via\":\"$jt\""
    if [ "$MERGED" = false ] && [ -n "$bref" ] && [ -n "$R_MAIN" ]; then
      merge_conflicts_v fc_main "$R_MAIN" "$bref"
      forecast_warning "$fc_main" "$MAIN"
    fi

    # hotfixes finished out of version order: allowed, but say so
    if [ "$PROBE" = finish-hotfix ]; then
      local hot_all="" hot_open="" hb
      list_branches_v hot_all "${HOTFIX_PREFIX}*"
      open_hotfixes_v hot_open "$hot_all"
      while IFS= read -r hb; do
        [ -z "$hb" ] || [ "$hb" = "$PROBE_BRANCH" ] && continue
        version_cmp "${hb#"$HOTFIX_PREFIX"}" "$PROBE_VERSION"
        [ "$VCMP" = -1 ] && add_probe_warning "$hb is still open with a lower version — finishing $PROBE_BRANCH first puts tags and $MAIN merges out of order (allowed; tell the user)"
      done <<<"$hot_open"
    fi

    # tag-exists (+ divergence guard)
    if tag_exists "$tag"; then
      local ttarget="" annotated=false tl=""
      tag_commit_v ttarget "$tag"
      lookup_line tl "$TAG_LINES" "$tag" || :
      case "$tl" in *" tag") annotated=true ;; esac
      add_step tag-exists true "\"annotated\":$annotated,\"target\":\"$ttarget\""
      if [ -n "$main_merge_sha" ] && [ "$ttarget" != "$main_merge_sha" ]; then
        add_probe_warning "tag $tag points at $ttarget but the merge commit on $MAIN is $main_merge_sha — do NOT retag silently, investigate first"
      fi
    else
      add_step tag-exists false
    fi

    # tag-pushed
    if [ "$LS_REMOTE_OK" = 1 ]; then
      local rtags="" rsha="" rplain="" local_sha=""
      capture_all rtags git ls-remote --tags origin "$tag" "$tag^{}"
      while IFS= read -r line; do
        case "$line" in
          *$'\t'"refs/tags/$tag^{}") rsha=${line%%$'\t'*} ;;
          *$'\t'"refs/tags/$tag") rplain=${line%%$'\t'*} ;;
        esac
      done <<<"$rtags"
      [ -z "$rsha" ] && rsha=$rplain
      tag_commit_v local_sha "$tag"
      if [ -z "$rsha" ]; then
        add_step tag-pushed false
      elif [ -n "$local_sha" ] && [ "$rsha" != "$local_sha" ]; then
        add_step tag-pushed false "\"detail\":\"remote tag points at $rsha, local at $local_sha\""
        add_probe_warning "tag $tag exists on origin with a DIFFERENT sha — stop and investigate (tag-sha-mismatch)"
      else
        add_step tag-pushed true
      fi
    else
      add_step tag-pushed false "\"detail\":\"cannot check: offline against a network remote\""
    fi

    # back-merged
    local bm_target=$DEVELOP bm_note=""
    if [ "$PROBE" = finish-hotfix ]; then
      local releases="" all_releases="" rcount=0
      list_branches_v all_releases "${RELEASE_PREFIX}*"
      open_releases_v releases "$all_releases"
      count_lines_v rcount "$releases"
      if [ "$rcount" -eq 1 ]; then
        bm_target=$releases; bm_note="open release takes the back-merge"
      elif [ "$rcount" -gt 1 ]; then
        add_step back-merged false "\"target\":\"ambiguous\",\"detail\":\"multiple open release branches — ask the user\""
        bm_target=""
      elif [ -n "$all_releases" ]; then
        bm_note="release branch(es) present but already shipped — $DEVELOP takes the back-merge"
      fi
    fi
    if [ -n "$bm_target" ]; then
      local tref="" src="" extra=""
      branch_ref_v tref "$bm_target"
      if tag_exists "$tag"; then tag_commit_v src "$tag"
      elif [ -n "$bref" ]; then src=$bref; fi
      json_str_v jb "$bm_target"
      [ -n "$bm_note" ] && { json_str_v jt "$bm_note"; extra=",\"detail\":\"$jt\""; }
      if [ -z "$tref" ] || [ -z "$src" ]; then
        add_step back-merged false "\"target\":\"$jb\",\"detail\":\"source or target ref missing\""
      elif git merge-base --is-ancestor "$src" "$tref" 2>/dev/null; then
        add_step back-merged true "\"target\":\"$jb\",\"mode\":\"ancestry\"$extra"
      elif content_absorbed_into "$tref" "$src"; then
        add_step back-merged true "\"target\":\"$jb\",\"mode\":\"content\"$extra"
      else
        add_step back-merged false "\"target\":\"$jb\",\"mode\":\"ancestry\"$extra"
        # before the tag exists the branch stands in for it (merge-branch
        # semantics; merge-tag usually conflicts less, never more on these paths)
        merge_conflicts_v fc_bm "$tref" "$src"
        forecast_warning "$fc_bm" "$bm_target"
      fi
    fi
    json_lines_v jfm "$fc_main"; json_lines_v jfb "$fc_bm"
    PROBE_FORECAST="\"main\":$jfm,\"backMerge\":$jfb"
  fi

  # remote-branch-deleted
  if [ "$LS_REMOTE_OK" = 1 ]; then
    local rheads=""
    capture rheads git ls-remote --heads origin "$PROBE_BRANCH"
    if [ -z "$rheads" ]; then add_step remote-branch-deleted true; else add_step remote-branch-deleted false; fi
  else
    add_step remote-branch-deleted false "\"detail\":\"cannot check: offline against a network remote\""
  fi

  # local-branch-deleted
  if local_branch_exists "$PROBE_BRANCH"; then
    add_step local-branch-deleted false
  else
    add_step local-branch-deleted true
  fi

  # gh-release
  if [ "$PROBE" != finish-feature ]; then
    if [ "$GH_MODE" = 1 ]; then
      local rel=""
      capture rel gh release view "$tag" --json tagName --jq .tagName
      if [ -n "$rel" ]; then add_step gh-release true; else add_step gh-release false; fi
    else
      add_step gh-release false "\"detail\":\"gh unavailable ($GH_STATE)\""
    fi
  fi

  # homebrew-formula (only when a tap is configured): the formula url must ship this tag
  if [ "$PROBE" != finish-feature ] && homebrew_configured; then
    json_str_v jt "$HOMEBREW_TAP/$HOMEBREW_FORMULA"
    if [ "$GH_MODE" = 1 ]; then
      local formula="" shipped=""
      tap_formula_v formula
      if [ -z "$formula" ]; then
        add_step homebrew-formula false "\"formula\":\"$jt\",\"detail\":\"could not read the formula from the tap\""
      elif formula_has_tag "$formula" "$tag"; then
        add_step homebrew-formula true "\"formula\":\"$jt\""
      else
        formula_tag_v shipped "$formula"
        json_str_v jb "$shipped"
        add_step homebrew-formula false "\"formula\":\"$jt\",\"shipped\":\"$jb\",\"detail\":\"formula url does not point at $tag yet\""
      fi
    else
      add_step homebrew-formula false "\"formula\":\"$jt\",\"detail\":\"gh unavailable ($GH_STATE)\""
    fi
  fi

  json_str_v jb "$PROBE_BRANCH"; json_str_v jt "$PROBE_VERSION"
  printf '{"gitflowDoctor":"%s","probe":"%s","branch":"%s","version":"%s","steps":[%s],"warnings":[%s],"forecast":{%s}}\n' \
    "$DOCTOR_VERSION" "$PROBE" "$jb" "$jt" "$PROBE_STEPS" "$PROBE_WARNINGS" "$PROBE_FORECAST"
  exit 0
}

# ===========================================================================
# CONVENTIONS MODE — infer the house style from the last finishes on main so
# `init` can PROPOSE messages / tag settings (the agent writes nothing unasked)
# ===========================================================================
CONV_SAMPLE=5
PRERELEASE_WORDS=" alpha beta rc pre preview dev snapshot canary next nightly "

majority_v() { # varname newline-list -> most frequent line (first seen wins ties)
  local __mj_v=$1 __mj_a __mj_b __mj_n __mj_best="" __mj_bn=0
  clear_v "$__mj_v"
  while IFS= read -r __mj_a; do
    [ -z "$__mj_a" ] && continue
    __mj_n=0
    while IFS= read -r __mj_b; do [ "$__mj_b" = "$__mj_a" ] && __mj_n=$((__mj_n + 1)); done <<<"$2"
    [ "$__mj_n" -gt "$__mj_bn" ] && { __mj_best=$__mj_a; __mj_bn=$__mj_n; }
  done <<<"$2"
  [ -n "$__mj_best" ] && printf -v "$__mj_v" '%s' "$__mj_best"
  return 0
}

run_conventions() {
  local cands="" t v line sorted sampled="" n=0 total=0
  # candidates: tags on main that look like [v]X.Y.Z[-...]
  while IFS= read -r t; do
    [ -z "$t" ] && continue
    v=${t#v}
    [[ $v =~ $SEMVER_RE ]] || continue
    cands="$cands${cands:+$NL}$t"
  done <<<"$MERGED_TAGS"
  sort_by_version_v sorted "$cands" v
  count_lines_v total "$sorted"
  # the newest CONV_SAMPLE tags
  local skip=$((total - CONV_SAMPLE)) i=0
  while IFS= read -r t; do
    [ -z "$t" ] && continue
    i=$((i + 1)); [ "$i" -le "$skip" ] && continue
    sampled="$sampled${sampled:+$NL}$t"; n=$((n + 1))
  done <<<"$sorted"

  # tag prefix / type / message votes
  local subj_lines="" pfx_votes="" type_votes="" tagmsg_votes="" tl typ tsub tmpl targets="" rest
  capture_all subj_lines git for-each-ref --format='%(refname:short)%09%(objecttype)%09%(contents:subject)' refs/tags
  while IFS= read -r t; do
    [ -z "$t" ] && continue
    case "$t" in v[0-9]*) pfx_votes="$pfx_votes${pfx_votes:+$NL}v" ;; *) pfx_votes="$pfx_votes${pfx_votes:+$NL}none" ;; esac
    tl=""; lookup_line tl "$TAG_LINES" "$t" || :
    typ=${tl##* }
    case "$typ" in tag) type_votes="$type_votes${type_votes:+$NL}annotated" ;; *) type_votes="$type_votes${type_votes:+$NL}lightweight" ;; esac
    rest=${tl#* }; targets="$targets ${rest%% *}"
    if [ "$typ" = tag ]; then
      while IFS= read -r line; do
        case "$line" in "$t"$'\t'*) : ;; *) continue ;; esac
        tsub=${line#*$'\t'}; tsub=${tsub#*$'\t'}
        template_v tmpl "$tsub" "" "$t" "${t#v}"
        tagmsg_votes="$tagmsg_votes${tagmsg_votes:+$NL}$tmpl"
        break
      done <<<"$subj_lines"
    fi
  done <<<"$sampled"

  # main merges at the tag targets, and develop merges that took them back
  local main_info="" dev_merges="" main_votes="" bm_votes="" strat_votes=""
  if [ -n "${targets// /}" ]; then
    # shellcheck disable=SC2086 # targets are shas, split on purpose
    capture_all main_info git log --no-walk=unsorted --format='%H %P%x09%s' $targets
  fi
  [ -n "$R_DEV" ] && capture_all dev_merges git log --first-parent --merges -n "$SCAN_DEPTH" --format='%H %P%x09%s' "$R_DEV"
  local m p1 p2 msub br ver dline dp2 dsub
  while IFS= read -r t; do
    [ -z "$t" ] && continue
    tl=""; lookup_line tl "$TAG_LINES" "$t" || :
    rest=${tl#* }; m=${rest%% *}
    ver=${t#v}
    line=""
    while IFS= read -r line; do case "$line" in "$m "*) break ;; esac; line=""; done <<<"$main_info"
    [ -z "$line" ] && continue
    msub=${line#*$'\t'}; line=${line%%$'\t'*}
    # shellcheck disable=SC2086 # shas split on purpose
    set -- $line
    [ $# -ge 3 ] || continue # the tag target is not a merge commit
    p2=$3
    br=""
    case "$msub" in
      *"$HOTFIX_PREFIX$ver"*) br="$HOTFIX_PREFIX$ver" ;;
      *"$RELEASE_PREFIX$ver"*) br="$RELEASE_PREFIX$ver" ;;
    esac
    template_v tmpl "$msub" "$br" "$t" "$ver"
    main_votes="$main_votes${main_votes:+$NL}$tmpl"
    while IFS= read -r dline; do
      [ -z "$dline" ] && continue
      dsub=${dline#*$'\t'}; dline=${dline%%$'\t'*}
      # shellcheck disable=SC2086 # shas split on purpose
      set -- $dline
      [ $# -ge 3 ] || continue
      dp2=$3
      if [ "$dp2" = "$m" ]; then strat_votes="$strat_votes${strat_votes:+$NL}merge-tag"
      elif [ "$dp2" = "$p2" ]; then strat_votes="$strat_votes${strat_votes:+$NL}merge-branch"
      else continue; fi
      template_v tmpl "$dsub" "$br" "$t" "$ver"
      bm_votes="$bm_votes${bm_votes:+$NL}$tmpl"
      break
    done <<<"$dev_merges"
  done <<<"$sampled"

  # version scheme: a non-prerelease word used as X.Y.Z-<word>.N at least twice
  local words="" w scheme_json='{"scheme":"semver"}' wbest=""
  while IFS= read -r t; do
    [ -z "$t" ] && continue
    v=${t#v}
    [[ $v =~ ^[0-9]+\.[0-9]+\.[0-9]+-([A-Za-z]+)\.[0-9]+$ ]] || continue
    w=${BASH_REMATCH[1]}
    case "$PRERELEASE_WORDS" in *" $w "*) continue ;; esac
    words="$words${words:+$NL}$w"
  done <<<"$sorted"
  majority_v wbest "$words"
  if [ -n "$wbest" ]; then
    local wn=0; while IFS= read -r w; do [ "$w" = "$wbest" ] && wn=$((wn + 1)); done <<<"$words"
    [ "$wn" -ge 2 ] && scheme_json="{\"scheme\":\"suffix-counter\",\"hotfixPattern\":\"{base}-$wbest.{n}\"}"
  fi

  local out="" best j msgs=""
  json_str_v j "$MAIN"; out="\"main\":\"$j\",\"sampled\":$n"
  majority_v best "$pfx_votes"
  case "$best" in v) out="$out,\"tagPrefix\":\"v\"" ;; none) out="$out,\"tagPrefix\":\"\"" ;; esac
  majority_v best "$type_votes"; [ -n "$best" ] && out="$out,\"tagType\":\"$best\""
  majority_v best "$main_votes"; [ -n "$best" ] && { json_str_v j "$best"; msgs="\"mergeToMain\":\"$j\""; }
  majority_v best "$bm_votes"; [ -n "$best" ] && { json_str_v j "$best"; msgs="$msgs${msgs:+,}\"backMerge\":\"$j\""; }
  majority_v best "$tagmsg_votes"; [ -n "$best" ] && { json_str_v j "$best"; msgs="$msgs${msgs:+,}\"tag\":\"$j\""; }
  out="$out,\"messages\":{$msgs}"
  majority_v best "$strat_votes"; [ -n "$best" ] && out="$out,\"backmergeStrategy\":\"$best\""
  out="$out,\"versionScheme\":$scheme_json"
  printf '{"gitflowDoctor":"%s","conventions":{%s}}\n' "$DOCTOR_VERSION" "$out"
  exit 0
}

[ -n "$PROBE" ] && run_probe
[ "$CONVENTIONS" = 1 ] && run_conventions

# ===========================================================================
# MERGE-PROOF MODE — evidence for a staged conflict resolution (read-only)
# ===========================================================================
diff_body_v() { # varname git-diff-args... -> the +/- lines after the first hunk header
  local __db_v=$1 __db_out="" __db_line __db_acc="" __db_in=0; shift
  capture_all __db_out git diff -U0 --no-color --no-ext-diff --no-textconv "$@"
  while IFS= read -r __db_line; do
    case "$__db_line" in "@@"*) __db_in=1; continue ;; esac
    [ "$__db_in" = 1 ] || continue
    case "$__db_line" in [+-]*) __db_acc="$__db_acc$NL$__db_line" ;; esac
  done <<<"$__db_out"
  clear_v "$__db_v"
  [ -n "$__db_acc" ] && printf -v "$__db_v" '%s' "$__db_acc"
  return 0
}

text_stats() { # content -> TS_LINES TS_CR TS_BOM(true/false) TS_MARKERS(true/false)
  local __ts_line __ts_first=1
  TS_LINES=0; TS_CR=0; TS_BOM=false; TS_MARKERS=false
  while IFS= read -r __ts_line || [ -n "$__ts_line" ]; do
    TS_LINES=$((TS_LINES + 1))
    if [ "$__ts_first" = 1 ]; then
      __ts_first=0
      case "$__ts_line" in $'\xef\xbb\xbf'*) TS_BOM=true ;; esac
    fi
    case "$__ts_line" in *$'\r') TS_CR=$((TS_CR + 1)); __ts_line=${__ts_line%$'\r'} ;; esac
    case "$__ts_line" in '<<<<<<<'|'<<<<<<< '*|'======='|'>>>>>>>'|'>>>>>>> '*|'|||||||'|'||||||| '*) TS_MARKERS=true ;; esac
  done <<<"$1"
}

validator_for() { # path -> VALIDATOR (xml|json|yaml|"")
  case "$1" in
    *.xml|*.config|*.csproj|*.vbproj|*.fsproj|*.props|*.targets|*.resx|*.xaml|*.svg) VALIDATOR=xml ;;
    *.json) VALIDATOR=json ;;
    *.yml|*.yaml) VALIDATOR=yaml ;;
    *) VALIDATOR="" ;;
  esac
}

run_merge_proof() {
  local theirs="" ours="" base="" paths="" unmerged="" line f files="" jf state
  capture theirs git rev-parse -q --verify MERGE_HEAD
  if [ -z "$theirs" ]; then
    printf '{"gitflowDoctor":"%s","mergeProof":{"merging":false}}\n' "$DOCTOR_VERSION"
    exit 0
  fi
  capture ours git rev-parse -q --verify HEAD
  capture base git merge-base "$ours" "$theirs"
  merge_conflicts_v paths "$ours" "$theirs"
  capture_all unmerged git ls-files -u
  while IFS= read -r line; do # "mode sha stage<TAB>path": keep conflicted paths merge-tree may not name
    [ -z "$line" ] && continue
    f=${line#*$'\t'}
    case "$NL$paths$NL" in *"$NL$f$NL"*) : ;; *) paths="$paths${paths:+$NL}$f" ;; esac
  done <<<"$unmerged"

  local their_change our_change ours_to_res theirs_to_res res_txt ours_txt a b m e bom v
  local ours_lines ours_cr ours_bom
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    json_str_v jf "$f"
    case "$NL$unmerged" in *$'\t'"$f$NL"*|*$'\t'"$f") state=unresolved ;; *) state=resolved ;; esac
    if [ "$state" = unresolved ]; then
      files="$files${files:+,}{\"path\":\"$jf\",\"state\":\"unresolved\",\"verdict\":\"unresolved\"}"
      continue
    fi
    diff_body_v their_change "$base" "$theirs" -- "$f"
    diff_body_v our_change "$base" "$ours" -- "$f"
    diff_body_v ours_to_res --cached "$ours" -- "$f"
    diff_body_v theirs_to_res --cached "$theirs" -- "$f"
    a=false; [ "$ours_to_res" = "$their_change" ] && a=true
    b=false; [ "$theirs_to_res" = "$our_change" ] && b=true
    capture_all ours_txt git show "$ours:$f"
    capture_all res_txt git show ":0:$f"
    text_stats "$ours_txt"; ours_lines=$TS_LINES; ours_cr=$TS_CR; ours_bom=$TS_BOM
    text_stats "$res_txt"; m=$TS_MARKERS
    e=false
    if { [ "$ours_cr" -eq 0 ] && [ "$TS_CR" -eq 0 ]; } || { [ "$ours_cr" -eq "$ours_lines" ] && [ "$TS_CR" -eq "$TS_LINES" ]; }; then e=true; fi
    bom=false; [ "$ours_bom" = "$TS_BOM" ] && bom=true
    validator_for "$f"
    v=review
    [ "$a" = true ] && [ "$b" = true ] && [ "$m" = false ] && [ "$e" = true ] && [ "$bom" = true ] && v=consistent
    files="$files${files:+,}{\"path\":\"$jf\",\"state\":\"resolved\",\"oursPlusTheirChange\":$a,\"theirsPlusOurChange\":$b,\"markers\":$m,\"eolPreserved\":$e,\"bomPreserved\":$bom,\"validator\":\"$VALIDATOR\",\"verdict\":\"$v\"}"
  done <<<"$paths"
  printf '{"gitflowDoctor":"%s","mergeProof":{"merging":true,"ours":"%s","theirs":"%s","base":"%s","files":[%s]}}\n' \
    "$DOCTOR_VERSION" "$ours" "$theirs" "$base" "$files"
  exit 0
}
[ "$MERGE_PROOF" = 1 ] && run_merge_proof

# ===========================================================================
# CHECKS
# ===========================================================================

# --- A.1 environment --------------------------------------------------------
if [ -z "$ORIGIN_URL" ]; then
  json_arr_v FIX "git remote add origin <url>"
  fail_check env-no-origin critical "no 'origin' remote configured" "" "$FIX" env-no-origin
else
  ok_check env-no-origin
fi

if [ -n "$ORIGIN_URL" ] && [ -z "$SLUG" ]; then
  json_str_v J "$ORIGIN_URL"
  fail_check env-origin-not-github info "origin is not a github.com remote — gh checks disabled" \
    "\"origin\":\"$J\"" "[]" env-origin-not-github
else
  ok_check env-origin-not-github
fi

case "$GH_STATE" in
  gh-missing|gh-unauthenticated)
    json_arr_v FIX "gh auth login"
    fail_check env-gh-unavailable warning "gh CLI unavailable ($GH_STATE) — GitHub checks skipped" \
      "\"state\":\"$GH_STATE\"" "$FIX" env-gh-unavailable ;;
  offline) skip_check env-gh-unavailable offline ;;
  *) ok_check env-gh-unavailable ;;
esac

if [ "$FETCH_FAILED" = 1 ]; then
  json_arr_v FIX "git fetch origin --prune --tags"
  fail_check env-fetch-failed warning "git fetch origin failed — remote-tracking data may be stale" "" "$FIX" env-fetch-failed
else
  ok_check env-fetch-failed
fi

if [ -z "$R_MAIN" ]; then
  json_str_v J "$MAIN"; json_arr_v FIX "run: gitdoctor init"
  fail_check env-missing-main critical "branch '$MAIN' not found locally or on origin" "\"branch\":\"$J\"" "$FIX" env-missing-main
else
  ok_check env-missing-main
fi
if [ -z "$R_DEV" ]; then
  json_str_v J "$DEVELOP"; json_arr_v FIX "run: gitdoctor init"
  fail_check env-missing-develop critical "branch '$DEVELOP' not found locally or on origin" "\"branch\":\"$J\"" "$FIX" env-missing-develop
else
  ok_check env-missing-develop
fi

if [ "$SHALLOW" = 1 ]; then
  json_arr_v FIX "git fetch --unshallow origin"
  fail_check env-shallow-clone warning "shallow clone — ancestry checks are unreliable (confidence lowered)" "" "$FIX" env-shallow-clone
else
  ok_check env-shallow-clone
fi
ANCESTRY_CONF=high; [ "$SHALLOW" = 1 ] && ANCESTRY_CONF=low

if [ "$MERGETREE_OK" = 0 ]; then
  json_arr_v FIX "upgrade git to >= 2.38"
  fail_check env-git-too-old warning "git $GITV < 2.38 — conflict prediction and content-equivalence disabled" \
    "\"version\":\"$GITV\"" "$FIX" env-git-too-old
else
  ok_check env-git-too-old
fi

# --- A.2 worktree ------------------------------------------------------------
if any_enabled dirty-worktree; then
  PORC=""
  capture_all PORC git status --porcelain
  if [ -n "$PORC" ]; then
    staged=0; unstaged=0; untracked=0
    while IFS= read -r line; do
      [ -z "$line" ] && continue
      case "$line" in
        '??'*) untracked=$((untracked + 1)) ;;
        *)
          case "${line:0:1}" in [MADRCT]) staged=$((staged + 1)) ;; esac
          case "${line:1:1}" in [MADRCT]) unstaged=$((unstaged + 1)) ;; esac ;;
      esac
    done <<<"$PORC"
    json_arr_v FIX "git status" "git stash push -u" "or commit your work"
    fail_check dirty-worktree warning "worktree not clean ($staged staged, $unstaged unstaged, $untracked untracked)" \
      "\"staged\":$staged,\"unstaged\":$unstaged,\"untracked\":$untracked" "$FIX" dirty-worktree
  else
    ok_check dirty-worktree
  fi
fi

if [ -z "$CURRENT_BRANCH" ]; then
  HEADSHA=""
  capture HEADSHA git rev-parse --short HEAD
  json_arr_v FIX "git switch <branch>"
  fail_check detached-head warning "HEAD is detached" "\"head\":\"$HEADSHA\"" "$FIX" detached-head
else
  ok_check detached-head
fi

if any_enabled operation-in-progress; then
  GP=""
  capture_all GP git rev-parse --git-path MERGE_HEAD --git-path rebase-merge \
    --git-path rebase-apply --git-path CHERRY_PICK_HEAD --git-path REVERT_HEAD --git-path BISECT_LOG
  { IFS= read -r p_merge; IFS= read -r p_rbm; IFS= read -r p_rba
    IFS= read -r p_chp; IFS= read -r p_rev; IFS= read -r p_bis; } <<<"$GP"
  op=""
  [ -n "${p_bis:-}" ] && [ -e "$p_bis" ] && op="bisect"
  [ -n "${p_rev:-}" ] && [ -e "$p_rev" ] && op="revert"
  [ -n "${p_chp:-}" ] && [ -e "$p_chp" ] && op="cherry-pick"
  [ -n "${p_rba:-}" ] && [ -d "$p_rba" ] && op="rebase"
  [ -n "${p_rbm:-}" ] && [ -d "$p_rbm" ] && op="rebase"
  [ -n "${p_merge:-}" ] && [ -e "$p_merge" ] && op="merge"
  if [ -n "$op" ]; then
    json_arr_v FIX "git $op --abort" "or resolve and continue the $op"
    fail_check operation-in-progress critical "a $op is in progress — finish or abort it first" \
      "\"operation\":\"$op\"" "$FIX" operation-in-progress
  else
    ok_check operation-in-progress
  fi
fi

# --- A.3 local <-> origin sync (main + develop) -------------------------------
sync_check() { # branch-name is-main(1/0)
  local b=$1 is_main=$2 counts="" ahead behind
  if ! local_branch_exists "$b" || ! remote_branch_exists "$b"; then
    skip_check sync-status "no-local-or-remote-branch" "sync check for $b skipped"
    return
  fi
  capture counts git rev-list --left-right --count "refs/heads/$b...refs/remotes/origin/$b"
  ahead=${counts%%[[:space:]]*}; behind=${counts##*[[:space:]]}
  ahead=${ahead:-0}; behind=${behind:-0}
  local J FIX
  json_str_v J "$b"
  if [ "$ahead" -gt 0 ] && [ "$behind" -gt 0 ]; then
    json_arr_v FIX "git log --oneline --left-right $b...origin/$b" "reconcile manually — never force-push shared branches"
    fail_check sync-diverged critical "local $b and origin/$b have diverged ($ahead vs $behind commits)" \
      "\"branch\":\"$J\",\"ahead\":$ahead,\"behind\":$behind" "$FIX" sync-diverged high "$b"
  elif [ "$behind" -gt 0 ]; then
    json_arr_v FIX "git switch $b" "git merge --ff-only origin/$b"
    fail_check sync-behind warning "local $b is $behind commit(s) behind origin/$b" \
      "\"branch\":\"$J\",\"behind\":$behind" "$FIX" sync-behind high "$b"
  elif [ "$ahead" -gt 0 ]; then
    local sev=warning
    [ "$is_main" = 1 ] && sev=critical
    json_arr_v FIX "verify the commits are legitimate: git log origin/$b..$b" "git push origin $b"
    fail_check sync-ahead "$sev" "local $b is $ahead commit(s) ahead of origin/$b (unpushed)" \
      "\"branch\":\"$J\",\"ahead\":$ahead" "$FIX" sync-ahead high "$b"
  else
    ok_check sync-status
  fi
}
if any_enabled sync-behind sync-ahead sync-diverged; then
  sync_check "$MAIN" 1
  sync_check "$DEVELOP" 0
fi

# --- A.4 topology + A.5/A.6 checks that need both branches -------------------
TOPO_IDS="missing-back-merge back-merge-content-only untagged-merge-on-main direct-commit-on-main wrong-base-feature wrong-base-hotfix release-develop-drift flow-branch-behind-main multiple-release-branches multiple-hotfix-branches orphaned-release-branch orphaned-hotfix-branch release-version-collision version-file-tag-mismatch changelog-tag-mismatch tag-not-on-main branch-stale-merged branch-stale-inactive"
if [ -z "$R_MAIN" ] || [ -z "$R_DEV" ]; then
  for id in $TOPO_IDS; do skip_check "$id" "missing-main-or-develop"; done
else
  # gh-derived sets shared by several checks
  GH_MERGED_HEADS=""
  GH_MAIN_PR_LINES=""
  if [ "$GH_MODE" = 1 ] && any_enabled untagged-merge-on-main direct-commit-on-main branch-stale-merged; then
    capture_all GH_MERGED_HEADS gh pr list --state merged --limit 100 --json headRefName --jq '.[].headRefName'
    capture_all GH_MAIN_PR_LINES gh pr list --base "$MAIN" --state merged --limit 50 --json headRefName,mergeCommit --jq '.[] | "\(.headRefName) \(.mergeCommit.oid)"'
  fi

  SINCE_ARG=""
  [ -n "$OLDEST_TAG" ] && SINCE_ARG="$OLDEST_TAG.."

  # missing-back-merge
  if any_enabled missing-back-merge back-merge-content-only; then
    BM_COUNT=""
    capture BM_COUNT git rev-list --count "$R_DEV..$R_MAIN"
    BM_COUNT=${BM_COUNT:-0}
    if [ "$BM_COUNT" -gt 0 ]; then
      BM_SHAS=""
      capture_all BM_SHAS git rev-list -n 10 "$R_DEV..$R_MAIN"
      # shellcheck disable=SC2086
      json_arr_v BM_ARR $BM_SHAS
      content_only=0
      CHERRY=""
      capture_all CHERRY git cherry "$R_DEV" "$R_MAIN"
      if [ -n "$CHERRY" ]; then
        case "$NL$CHERRY" in *"$NL+"*) : ;; *) content_only=1 ;; esac
      fi
      [ "$content_only" = 0 ] && content_absorbed_into_dev "$R_MAIN" && content_only=1
      if [ "$content_only" = 1 ]; then
        json_arr_v FIX "optional ancestry repair: git switch $DEVELOP && git merge --no-ff origin/$MAIN && git push origin $DEVELOP"
        fail_check back-merge-content-only info "$MAIN has $BM_COUNT commit(s) not in $DEVELOP by ancestry, but the content is already absorbed (squash back-merge?)" \
          "\"ahead\":$BM_COUNT,\"commits\":$BM_ARR,\"patchEquivalent\":true" "$FIX" missing-back-merge medium
      else
        cp=false
        conflicts_predicted "$R_DEV" "$R_MAIN" && cp=true
        json_arr_v FIX "git switch $DEVELOP" "git merge --no-ff origin/$MAIN" "git push origin $DEVELOP"
        fail_check missing-back-merge critical "$MAIN has $BM_COUNT commit(s) not in $DEVELOP" \
          "\"ahead\":$BM_COUNT,\"commits\":$BM_ARR,\"patchEquivalent\":false,\"conflictsPredicted\":$cp" \
          "$FIX" missing-back-merge "$ANCESTRY_CONF"
      fi
    else
      ok_check missing-back-merge
    fi
  fi

  # untagged-merge-on-main
  if any_enabled untagged-merge-on-main; then
    MERGE_SHAS=""
    capture_all MERGE_SHAS git rev-list --first-parent --merges -n "$SCAN_DEPTH" "${SINCE_ARG}${R_MAIN}"
    untagged=""
    while IFS= read -r sha; do
      [ -z "$sha" ] && continue
      sha_is_tagged "$sha" && continue
      glob_in_list "$sha" "$IGNORE_SHAS" && continue
      untagged="$untagged $sha"
    done <<<"$MERGE_SHAS"
    if [ "$GH_MODE" = 1 ] && [ -n "$GH_MAIN_PR_LINES" ]; then
      while IFS= read -r line; do
        [ -z "$line" ] && continue
        head=${line%% *}; sha=${line##* }
        case "$head" in
          "$RELEASE_PREFIX"*|"$HOTFIX_PREFIX"*)
            [ -z "$sha" ] && continue
            sha_is_tagged "$sha" && continue
            glob_in_list "$sha" "$IGNORE_SHAS" && continue
            case " $untagged " in *" $sha "*) : ;; *) untagged="$untagged $sha" ;; esac ;;
        esac
      done <<<"$GH_MAIN_PR_LINES"
    fi
    if [ -n "${untagged// /}" ]; then
      # shellcheck disable=SC2086
      set -- $untagged
      unt_count=$#
      first_sha=$1
      json_arr_v UNT_ARR "$@"
      json_arr_v FIX "git tag -a ${TAG_PREFIX}X.Y.Z $first_sha -m \"Release X.Y.Z\"" "git push origin ${TAG_PREFIX}X.Y.Z"
      fail_check untagged-merge-on-main warning "$unt_count release/hotfix merge(s) on $MAIN carry no tag" \
        "\"commits\":$UNT_ARR" "$FIX" untagged-merge-on-main high "$first_sha"
    else
      ok_check untagged-merge-on-main
    fi
  fi

  # direct-commit-on-main
  if any_enabled direct-commit-on-main; then
    ROOTS=""
    capture_all ROOTS git rev-list --max-parents=0 -n 5 "$R_MAIN"
    DC_LINES=""
    capture_all DC_LINES git log --first-parent --no-merges -n "$SCAN_DEPTH" --format='%H %s' "${SINCE_ARG}${R_MAIN}"
    direct=""
    dconf=high; [ "$GH_MODE" = 1 ] || dconf=medium
    while IFS= read -r line; do
      [ -z "$line" ] && continue
      sha=${line%% *}; subj=${line#* }
      case "$NL$ROOTS$NL" in *"$NL$sha$NL"*) continue ;; esac
      sha_is_tagged "$sha" && continue
      glob_in_list "$sha" "$IGNORE_SHAS" && continue
      if [ "$GH_MODE" = 1 ] && [ -n "$GH_MAIN_PR_LINES" ]; then
        case "$GH_MAIN_PR_LINES" in *" $sha"*) continue ;; esac
      elif [[ $subj =~ \(\#[0-9]+\)$ ]]; then
        continue
      fi
      direct="$direct $sha"
    done <<<"$DC_LINES"
    if [ -n "${direct// /}" ]; then
      # shellcheck disable=SC2086
      set -- $direct
      dir_count=$#
      first_sha=$1
      json_arr_v DIR_ARR "$@"
      json_arr_v FIX "verify each commit is also in $DEVELOP (else back-merge)" "enable branch protection on $MAIN"
      fail_check direct-commit-on-main warning "$dir_count commit(s) landed directly on $MAIN (not via a tagged merge or PR)" \
        "\"commits\":$DIR_ARR" "$FIX" direct-commit-on-main "$dconf" "$first_sha"
    else
      ok_check direct-commit-on-main
    fi
  fi

  # wrong-base: feature + release cut from develop
  FEATURES=""; RELEASES=""; HOTFIXES=""
  list_branches_v FEATURES "${FEATURE_PREFIX}*"
  list_branches_v RELEASES "${RELEASE_PREFIX}*"
  list_branches_v HOTFIXES "${HOTFIX_PREFIX}*"
  OPEN_RELEASES=""; open_releases_v OPEN_RELEASES "$RELEASES" # shipped leftovers are not open
  BM_OPEN=0; [ "${BM_COUNT:-0}" -gt 0 ] 2>/dev/null && BM_OPEN=1

  if any_enabled wrong-base-feature; then
    wb_found=0
    while IFS= read -r br; do
      [ -z "$br" ] && continue
      branch_ref_v ref "$br"; [ -z "$ref" ] && continue
      mb=""
      capture mb git merge-base "$R_MAIN" "$ref"
      [ -z "$mb" ] && continue
      cnt=""
      capture cnt git rev-list --count "$R_DEV..$mb"
      if [ "${cnt:-0}" -gt 0 ]; then
        wb_found=1
        rel=""
        [ "$BM_OPEN" = 1 ] && rel=",\"relatedFinding\":\"missing-back-merge\""
        json_str_v J "$br"
        json_arr_v FIX "git rebase --onto origin/$DEVELOP \$(git merge-base origin/$MAIN $br) $br" "or recreate the branch from $DEVELOP"
        fail_check wrong-base-feature warning "$br contains $cnt $MAIN-only commit(s) — branched from $MAIN instead of $DEVELOP?" \
          "\"branch\":\"$J\",\"mainOnlyCommits\":$cnt$rel" "$FIX" wrong-base-feature "$ANCESTRY_CONF" "$br"
      fi
    done <<<"$FEATURES$NL$RELEASES"
    [ "$wb_found" = 0 ] && ok_check wrong-base-feature
  fi

  if any_enabled wrong-base-hotfix; then
    wh_found=0
    while IFS= read -r br; do
      [ -z "$br" ] && continue
      branch_ref_v ref "$br"; [ -z "$ref" ] && continue
      mb=""
      capture mb git merge-base "$R_DEV" "$ref"
      [ -z "$mb" ] && continue
      cnt=""
      capture cnt git rev-list --count "$R_MAIN..$mb"
      if [ "${cnt:-0}" -gt 0 ]; then
        wh_found=1
        json_str_v J "$br"
        json_arr_v FIX "git switch -c $br-rebased origin/$MAIN" "git cherry-pick <fix commits>" "replace $br with the recreated branch"
        fail_check wrong-base-hotfix critical "$br contains $cnt $DEVELOP-only commit(s) — finishing it would ship unreleased work to production" \
          "\"branch\":\"$J\",\"developOnlyCommits\":$cnt" "$FIX" wrong-base-hotfix "$ANCESTRY_CONF" "$br"
      fi
    done <<<"$HOTFIXES"
    [ "$wh_found" = 0 ] && ok_check wrong-base-hotfix
  fi

  # release branch family
  if any_enabled multiple-release-branches; then
    rel_count=0
    count_lines_v rel_count "$OPEN_RELEASES"
    if [ "$rel_count" -gt "$MAX_RELEASES" ]; then
      # shellcheck disable=SC2086
      json_arr_v REL_ARR $OPEN_RELEASES
      json_arr_v FIX "finish or delete the older release before starting another"
      fail_check multiple-release-branches warning "$rel_count release branches open (max $MAX_RELEASES)" \
        "\"branches\":$REL_ARR" "$FIX" multiple-release-branches
    else
      ok_check multiple-release-branches
    fi
  fi

  if any_enabled release-develop-drift; then
    drift_found=0
    while IFS= read -r br; do
      [ -z "$br" ] && continue
      branch_ref_v ref "$br"; [ -z "$ref" ] && continue
      behind=""; pending=""
      capture behind git rev-list --count "$ref..$R_DEV"
      capture pending git rev-list --count "$R_DEV..$ref"
      if [ "${behind:-0}" -gt 0 ]; then
        drift_found=1
        sev=info; cp=false
        if conflicts_predicted "$R_DEV" "$ref"; then sev=warning; cp=true; fi
        json_str_v J "$br"
        json_arr_v FIX "nothing now — classic git flow resolves this at finish back-merge" "preview: git merge-tree --write-tree origin/$DEVELOP $br"
        fail_check release-develop-drift "$sev" "$DEVELOP moved $behind commit(s) ahead of $br (back-merge pending: ${pending:-0})" \
          "\"branch\":\"$J\",\"developAhead\":$behind,\"pendingBackMerge\":${pending:-0},\"conflictsPredicted\":$cp" \
          "$FIX" release-develop-drift high "$br"
      fi
    done <<<"$OPEN_RELEASES"
    [ "$drift_found" = 0 ] && ok_check release-develop-drift
  fi

  # open release/hotfix branches that main moved past: forecast both finish legs
  OPEN_HOTFIXES=""; open_hotfixes_v OPEN_HOTFIXES "$HOTFIXES"
  FB_FACTS="" # br US behind US main-conflicts-json (reused by multiple-hotfix-branches)
  if any_enabled flow-branch-behind-main multiple-hotfix-branches; then
    fb_found=0
    while IFS= read -r br; do
      [ -z "$br" ] && continue
      branch_ref_v ref "$br"; [ -z "$ref" ] && continue
      behind=""
      capture behind git rev-list --count "$ref..$R_MAIN"
      behind=${behind:-0}
      mc=""; dc=""
      if [ "$behind" -gt 0 ]; then
        merge_conflicts_v mc "$R_MAIN" "$ref"
        merge_conflicts_v dc "$R_DEV" "$ref"
      fi
      json_lines_v MCJ "$mc"; json_lines_v DCJ "$dc"
      FB_FACTS="$FB_FACTS${FB_FACTS:+$NL}$br$US$behind$US$MCJ"
      [ "$behind" -gt 0 ] || continue
      fb_found=1
      sev=info; title="$br is $behind commit(s) behind $MAIN"
      if [ -n "$mc$dc" ]; then
        sev=warning; count_lines_v nconf "$mc$NL$dc"
        title="$title — its finish would conflict ($nconf path(s); resolve on the branch first)"
      fi
      json_str_v J "$br"
      json_arr_v FIX "git switch $br && git merge origin/$MAIN" "resolve on $br (its author knows the change), then: git push origin $br"
      fail_check flow-branch-behind-main "$sev" "$title" \
        "\"branch\":\"$J\",\"behind\":$behind,\"conflicts\":{\"main\":$MCJ,\"develop\":$DCJ}" \
        "$FIX" flow-branch-behind-main "$ANCESTRY_CONF" "$br"
    done <<<"$OPEN_HOTFIXES$NL$OPEN_RELEASES"
    [ "$fb_found" = 0 ] && ok_check flow-branch-behind-main
  fi

  # several open hotfixes: show base, lag and conflicts in finish order
  if any_enabled multiple-hotfix-branches; then
    hot_count=0
    count_lines_v hot_count "$OPEN_HOTFIXES"
    if [ "$hot_count" -gt 1 ]; then
      sort_by_version_v SORTED_HOT "$OPEN_HOTFIXES" "$HOTFIX_PREFIX"
      HOT_ARR=""; first_hot=""
      while IFS= read -r br; do
        [ -z "$br" ] && continue
        [ -z "$first_hot" ] && first_hot=$br
        branch_ref_v ref "$br"
        base=""
        [ -n "$ref" ] && capture base git describe --tags --abbrev=0 --match "${TAG_PREFIX}[0-9]*" "$ref"
        fact=""; behind=0; MCJ="[]"
        while IFS= read -r fact; do
          case "$fact" in "$br$US"*) fact=${fact#*"$US"}; behind=${fact%%"$US"*}; MCJ=${fact#*"$US"}; break ;; esac
        done <<<"$FB_FACTS"
        json_str_v J "$br"; json_str_v JV "${br#"$HOTFIX_PREFIX"}"; json_str_v JB "$base"
        HOT_ARR="$HOT_ARR${HOT_ARR:+,}{\"branch\":\"$J\",\"version\":\"$JV\",\"base\":\"$JB\",\"behind\":$behind,\"mainConflicts\":$MCJ}"
      done <<<"$SORTED_HOT"
      json_str_v J "$first_hot"
      json_arr_v FIX "finish in version order, starting with $first_hot" "a branch behind $MAIN: merge $MAIN into it first (flow-branch-behind-main)"
      fail_check multiple-hotfix-branches info "$hot_count hotfix branches open at once — finish order matters" \
        "\"branches\":[$HOT_ARR],\"finishFirst\":\"$J\"" "$FIX" multiple-hotfix-branches
    else
      ok_check multiple-hotfix-branches
    fi
  fi

  if any_enabled orphaned-release-branch orphaned-hotfix-branch release-version-collision; then
    orph_found=0
    coll_found=0
    while IFS= read -r br; do
      [ -z "$br" ] && continue
      ver=""
      case "$br" in
        "$RELEASE_PREFIX"*) ver=${br#"$RELEASE_PREFIX"}; kind=release ;;
        "$HOTFIX_PREFIX"*) ver=${br#"$HOTFIX_PREFIX"}; kind=hotfix ;;
        *) continue ;;
      esac
      tag="${TAG_PREFIX}${ver}"
      if tag_exists "$tag"; then
        orph_found=1
        json_str_v J "$br"; json_str_v JT "$tag"
        if remote_branch_exists "$br"; then
          json_arr_v FIX "resume: gitdoctor finish (probe walk completes back-merge/deletion)" "or after verifying merge: git push origin --delete $br && git branch -d $br"
        else
          json_arr_v FIX "resume: gitdoctor finish (probe walk completes back-merge/deletion)" "or after verifying merge (local-only leftover): git branch -d $br"
        fi
        fail_check "orphaned-$kind-branch" warning "$br still exists but $tag is already tagged — an unfinished finish" \
          "\"branch\":\"$J\",\"tag\":\"$JT\"" "$FIX" orphaned-release-branch high "$br"
        continue
      fi
      if [ -n "$LATEST_TAG" ] && [[ $ver =~ $SEMVER_RE ]]; then
        latest_ver=${LATEST_TAG#"$TAG_PREFIX"}
        if version_le "$ver" "$latest_ver"; then
          coll_found=1
          pfx=$RELEASE_PREFIX; [ "$kind" = hotfix ] && pfx=$HOTFIX_PREFIX
          nv="<next-version>"; [ "$kind" = hotfix ] && [ -n "$NEXT_HOTFIX" ] && nv=$NEXT_HOTFIX
          json_str_v J "$br"; json_str_v JT "$LATEST_TAG"
          json_arr_v FIX "git branch -m $br $pfx$nv" "git push origin :$br $pfx$nv"
          fail_check release-version-collision warning "$br targets version $ver but $LATEST_TAG is already released" \
            "\"branch\":\"$J\",\"latestTag\":\"$JT\"" "$FIX" release-version-collision high "$br"
        fi
      fi
    done <<<"$RELEASES$NL$HOTFIXES"
    [ "$orph_found" = 0 ] && ok_check orphaned-release-branch
    [ "$coll_found" = 0 ] && ok_check release-version-collision
  fi

  # version-file <-> tag
  if any_enabled version-file-tag-mismatch; then
    if [ "$VF_COUNT" -eq 0 ]; then
      skip_check version-file-tag-mismatch not-configured
    elif [ -z "$LATEST_TAG" ]; then
      skip_check version-file-tag-mismatch no-semver-tags
    else
      latest_ver=${LATEST_TAG#"$TAG_PREFIX"}
      vf_bad=0
      i=0
      while [ "$i" -lt "$VF_COUNT" ]; do
        vf_path_v p "$i"; vf_pattern_v pat "$i"
        got=""
        extract_version_v got "$R_MAIN" "$p" "$pat"
        if [ -n "$got" ] && [ "$got" != "$latest_ver" ]; then
          vf_bad=1
          json_str_v J "$p"; json_str_v JG "$got"; json_str_v JL "$latest_ver"
          json_arr_v FIX "align on the next release/hotfix finish (version bump step)" "or hot-patch the file via a hotfix branch"
          fail_check version-file-tag-mismatch warning "$p on $MAIN says $got but the latest tag is $LATEST_TAG" \
            "\"file\":\"$J\",\"fileVersion\":\"$JG\",\"tagVersion\":\"$JL\"" "$FIX" version-file-tag-mismatch high "$p"
        fi
        i=$((i + 1))
      done
      [ "$vf_bad" = 0 ] && ok_check version-file-tag-mismatch
    fi
  fi

  # changelog <-> tag: the latest release must have a heading in the changelog on main
  if any_enabled changelog-tag-mismatch; then
    if [ -z "$CHANGELOG_FILE" ]; then
      skip_check changelog-tag-mismatch not-configured
    elif [ -z "$LATEST_TAG" ]; then
      skip_check changelog-tag-mismatch no-semver-tags
    else
      latest_ver=${LATEST_TAG#"$TAG_PREFIX"}
      CL_CONTENT=""
      capture_all CL_CONTENT git show "$R_MAIN:$CHANGELOG_FILE"
      cl_found=0
      if [ -n "$CL_CONTENT" ]; then
        ver_re=${latest_ver//./\\.}
        cl_re="(^|[^0-9.])${ver_re}([^0-9.]|$)"
        while IFS= read -r line; do
          case "$line" in "#"*) : ;; *) continue ;; esac
          if [[ $line =~ $cl_re ]]; then cl_found=1; break; fi
        done <<<"$CL_CONTENT"
      fi
      if [ "$cl_found" = 1 ]; then
        ok_check changelog-tag-mismatch
      else
        detail="no heading mentions $latest_ver"
        [ -z "$CL_CONTENT" ] && detail="file missing on $MAIN"
        json_str_v J "$CHANGELOG_FILE"; json_str_v JT "$LATEST_TAG"; json_str_v JL "$latest_ver"; json_str_v JD "$detail"
        json_arr_v FIX "add a '## $latest_ver' section to $CHANGELOG_FILE during the next release/hotfix finish" "or hot-patch it now via a hotfix branch (changelog-only change)"
        fail_check changelog-tag-mismatch warning "$CHANGELOG_FILE on $MAIN has no entry for $LATEST_TAG ($detail)" \
          "\"file\":\"$J\",\"tag\":\"$JT\",\"tagVersion\":\"$JL\",\"detail\":\"$JD\"" "$FIX" changelog-tag-mismatch high "$LATEST_TAG"
      fi
    fi
  fi

  # tag-not-on-main (membership in the merged-into-main tag list — zero spawns)
  if any_enabled tag-not-on-main; then
    tnm_found=0
    while IFS= read -r tl; do
      [ -z "$tl" ] && continue
      t=${tl%% *}
      is_semver_tag "$t" || continue
      if ! tag_on_main "$t"; then
        tnm_found=1
        rest=${tl#* }; tsha=${rest%% *}
        json_str_v J "$t"
        json_arr_v FIX "resume the finish so the tagged commit reaches $MAIN" "or retag the real release commit after investigating"
        fail_check tag-not-on-main warning "tag $t is not reachable from $MAIN — an interrupted finish?" \
          "\"tag\":\"$J\",\"target\":\"$tsha\"" "$FIX" tag-not-on-main "$ANCESTRY_CONF" "$t"
      fi
    done <<<"$TAG_LINES"
    [ "$tnm_found" = 0 ] && ok_check tag-not-on-main
  fi

  # branch hygiene: stale (merged / inactive)
  if any_enabled branch-stale-merged branch-stale-inactive; then
    BMBR=""
    list_branches_v BMBR "${BACKMERGE_PREFIX}*"
    sm_found=0; si_found=0
    while IFS= read -r br; do
      [ -z "$br" ] && continue
      branch_ref_v ref "$br"; [ -z "$ref" ] && continue
      method=""; conf=high; delflag="-d"
      if git merge-base --is-ancestor "$ref" "$R_DEV" 2>/dev/null; then
        method=ancestry
      elif [ "$GH_MODE" = 1 ] && [ -n "$GH_MERGED_HEADS" ]; then
        case "$NL$GH_MERGED_HEADS$NL" in *"$NL$br$NL"*) method="gh-pr"; delflag="-D" ;; esac
      fi
      if [ -z "$method" ] && content_absorbed_into_dev "$ref"; then
        method="content-equivalent"; conf=medium; delflag="-D"
      fi
      json_str_v J "$br"
      if [ -n "$method" ]; then
        sm_found=1
        json_arr_v FIX "git push origin --delete $br" "git branch $delflag $br"
        fail_check branch-stale-merged info "$br is already merged into $DEVELOP ($method) but not deleted" \
          "\"branch\":\"$J\",\"method\":\"$method\"" "$FIX" branch-stale-merged "$conf" "$br"
        continue
      fi
      line=""
      if remote_branch_exists "$br"; then lookup_line line "$REMOTE_LINES" "$br"; else lookup_line line "$LOCAL_LINES" "$br"; fi
      cdate=${line##* }
      case "$cdate" in ''|*[!0-9]*) continue ;; esac
      if [ $((NOW - cdate)) -gt $((STALE_DAYS * 86400)) ]; then
        si_found=1
        days=$(((NOW - cdate) / 86400))
        json_arr_v FIX "finish it, delete it, or revive: git rebase origin/$DEVELOP $br"
        fail_check branch-stale-inactive info "$br has had no commits for $days days" \
          "\"branch\":\"$J\",\"inactiveDays\":$days" "$FIX" branch-stale-inactive high "$br"
      fi
    done <<<"$FEATURES$NL$BMBR"
    [ "$sm_found" = 0 ] && ok_check branch-stale-merged
    [ "$si_found" = 0 ] && ok_check branch-stale-inactive
  fi
fi

# --- A.5 tag checks that need no main/develop --------------------------------
if any_enabled non-semver-tag; then
  ns_found=0
  while IFS= read -r tl; do
    [ -z "$tl" ] && continue
    t=${tl%% *}
    is_semver_tag "$t" && continue
    glob_in_list "$t" "$IGNORE_TAGS" && continue
    ns_found=1
    json_str_v J "$t"
    json_arr_v FIX "leave it (historic) or: git tag -d $t && git push origin :refs/tags/$t" "or add it to doctor.ignoreTags"
    fail_check non-semver-tag info "tag '$t' does not match ${TAG_PREFIX}X.Y.Z" "\"tag\":\"$J\"" "$FIX" non-semver-tag high "$t"
  done <<<"$TAG_LINES"
  [ "$ns_found" = 0 ] && ok_check non-semver-tag
fi

if any_enabled duplicate-tag-target; then
  dup_found=0
  seen_shas=" "
  dup_shas=" "
  while IFS= read -r tl; do
    [ -z "$tl" ] && continue
    t=${tl%% *}
    is_semver_tag "$t" || continue
    rest=${tl#* }; tsha=${rest%% *}
    case "$seen_shas" in
      *" $tsha "*)
        case "$dup_shas" in *" $tsha "*) : ;; *) dup_shas="$dup_shas$tsha " ;; esac ;;
      *) seen_shas="$seen_shas$tsha " ;;
    esac
  done <<<"$TAG_LINES"
  if [ "$dup_shas" != " " ]; then
    dup_tags=""
    while IFS= read -r tl; do
      [ -z "$tl" ] && continue
      t=${tl%% *}
      is_semver_tag "$t" || continue
      rest=${tl#* }; tsha=${rest%% *}
      case "$dup_shas" in *" $tsha "*) dup_tags="$dup_tags $t" ;; esac
    done <<<"$TAG_LINES"
    dup_found=1
    # shellcheck disable=SC2086
    json_arr_v DUP_ARR $dup_tags
    json_arr_v FIX "after confirming which is wrong: git tag -d <tag> && git push origin :refs/tags/<tag>"
    fail_check duplicate-tag-target warning "multiple semver tags point at the same commit" \
      "\"tags\":$DUP_ARR" "$FIX" duplicate-tag-target
  fi
  [ "$dup_found" = 0 ] && ok_check duplicate-tag-target
fi

if any_enabled tag-prefix-collision; then
  pc_found=0
  if [ -n "$TAG_PREFIX" ]; then
    while IFS= read -r tl; do
      [ -z "$tl" ] && continue
      t=${tl%% *}
      is_semver_tag "$t" || continue
      bare=${t#"$TAG_PREFIX"}
      if tag_exists "$bare"; then
        pc_found=1
        json_arr_v TARR "$t" "$bare"
        json_arr_v FIX "delete the unprefixed twin: git tag -d $bare && git push origin :refs/tags/$bare"
        fail_check tag-prefix-collision warning "both '$t' and '$bare' exist" "\"tags\":$TARR" "$FIX" tag-prefix-collision high "$t"
      fi
    done <<<"$TAG_LINES"
  fi
  [ "$pc_found" = 0 ] && ok_check tag-prefix-collision
fi

if any_enabled tag-lightweight-release; then
  lw_found=0
  while IFS= read -r tl; do
    [ -z "$tl" ] && continue
    t=${tl%% *}
    is_semver_tag "$t" || continue
    case "$tl" in
      *" commit")
        lw_found=1
        json_str_v J "$t"
        json_arr_v FIX "future tags: git tag -a" "optionally recreate: git tag -d $t && git tag -a $t <sha> -m ... && git push -f origin $t (coordinate first)"
        fail_check tag-lightweight-release info "release tag $t is lightweight, not annotated" "\"tag\":\"$J\"" "$FIX" tag-lightweight-release high "$t" ;;
    esac
  done <<<"$TAG_LINES"
  [ "$lw_found" = 0 ] && ok_check tag-lightweight-release
fi

# tag-unsigned (opt-in): annotated + carrying a GPG/SSH signature; one for-each-ref
if any_enabled tag-unsigned; then
  if [ "$REQUIRE_SIGNED_TAGS" = 0 ]; then
    skip_check tag-unsigned not-configured
  else
    SIGS=""
    capture_all SIGS git for-each-ref --format='%(refname:short)%09%(contents:signature)' refs/tags
    signed_tags=" "
    while IFS= read -r line; do
      case "$line" in *$'\t'*) : ;; *) continue ;; esac # continuation lines of a signature carry no tab
      t=${line%%$'\t'*}; sig=${line#*$'\t'}
      [ -n "$sig" ] && signed_tags="$signed_tags$t "
    done <<<"$SIGS"
    us_found=0
    while IFS= read -r tl; do
      [ -z "$tl" ] && continue
      t=${tl%% *}
      is_semver_tag "$t" || continue
      glob_in_list "$t" "$IGNORE_TAGS" && continue
      case "$tl" in *" tag") case "$signed_tags" in *" $t "*) continue ;; esac ;; esac
      us_found=1
      json_str_v J "$t"
      json_arr_v FIX "sign future tags: git tag -s ${TAG_PREFIX}X.Y.Z -m \"Release X.Y.Z\" (or git config tag.gpgSign true)" "verify: git tag -v $t"
      fail_check tag-unsigned warning "release tag $t is not signed (release.signedTags is on)" "\"tag\":\"$J\"" "$FIX" tag-unsigned high "$t"
    done <<<"$TAG_LINES"
    [ "$us_found" = 0 ] && ok_check tag-unsigned
  fi
fi

# tag-unpushed + tag-sha-mismatch (one ls-remote for all tags)
if any_enabled tag-unpushed tag-sha-mismatch; then
  if [ "$LS_REMOTE_OK" = 1 ]; then
    RTAGS=""
    capture_all RTAGS git ls-remote --tags origin
    up_found=0; mm_found=0
    while IFS= read -r tl; do
      [ -z "$tl" ] && continue
      t=${tl%% *}
      glob_in_list "$t" "$IGNORE_TAGS" && continue
      rest=${tl#* }; local_sha=${rest%% *}
      rsha=""; rplain=""
      while IFS= read -r rline; do
        case "$rline" in
          *$'\t'"refs/tags/$t^{}") rsha=${rline%%$'\t'*} ;;
          *$'\t'"refs/tags/$t") rplain=${rline%%$'\t'*} ;;
        esac
      done <<<"$RTAGS"
      [ -z "$rsha" ] && rsha=$rplain
      json_str_v J "$t"
      if [ -z "$rsha" ]; then
        up_found=1
        json_arr_v FIX "git push origin $t"
        fail_check tag-unpushed warning "tag $t exists locally but not on origin" "\"tag\":\"$J\"" "$FIX" tag-unpushed high "$t"
      elif [ -n "$local_sha" ] && [ "$rsha" != "$local_sha" ]; then
        mm_found=1
        json_arr_v FIX "investigate before ANY finish — never force-push tags" "git show $t / git ls-remote --tags origin $t"
        fail_check tag-sha-mismatch critical "tag $t points at $local_sha locally but $rsha on origin" \
          "\"tag\":\"$J\",\"local\":\"$local_sha\",\"remote\":\"$rsha\"" "$FIX" tag-sha-mismatch high "$t"
      fi
    done <<<"$TAG_LINES"
    [ "$up_found" = 0 ] && ok_check tag-unpushed
    [ "$mm_found" = 0 ] && ok_check tag-sha-mismatch
  else
    skip_check tag-unpushed "offline-network-remote"
    skip_check tag-sha-mismatch "offline-network-remote"
  fi
fi

# --- A.6 branch naming --------------------------------------------------------
if any_enabled branch-bad-version-name; then
  RELS=""; HOTS=""
  list_branches_v RELS "${RELEASE_PREFIX}*"
  list_branches_v HOTS "${HOTFIX_PREFIX}*"
  bn_found=0
  while IFS= read -r br; do
    [ -z "$br" ] && continue
    ver=""
    case "$br" in
      "$RELEASE_PREFIX"*) ver=${br#"$RELEASE_PREFIX"} ;;
      "$HOTFIX_PREFIX"*) ver=${br#"$HOTFIX_PREFIX"}
        counter_version_parts "$ver" && continue ;; # suffix-counter hotfix names are first-class
      *) continue ;;
    esac
    if ! [[ $ver =~ $RELEASE_NAME_RE ]]; then
      bn_found=1
      json_str_v J "$br"
      json_arr_v FIX "git branch -m $br <prefix>/X.Y.Z" "git push origin :$br <prefix>/X.Y.Z"
      fail_check branch-bad-version-name warning "$br: suffix '$ver' is not a bare X.Y.Z version" \
        "\"branch\":\"$J\"" "$FIX" branch-bad-version-name high "$br"
    fi
  done <<<"$RELS$NL$HOTS"
  [ "$bn_found" = 0 ] && ok_check branch-bad-version-name
fi

if any_enabled branch-unrecognized; then
  KNOWN_PREFIX_LIST="$FEATURE_PREFIX*,$RELEASE_PREFIX*,$HOTFIX_PREFIX*,$BACKMERGE_PREFIX*"
  bu_found=0
  seen=" "
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    br=${line%% *}
    case "$seen" in *" $br "*) continue ;; esac
    seen="$seen$br "
    case "$br" in "$MAIN"|"$DEVELOP"|HEAD) continue ;; esac
    glob_in_list "$br" "$KNOWN_PREFIX_LIST" && continue
    glob_in_list "$br" "$IGNORE_BRANCHES" && continue
    bu_found=1
    json_str_v J "$br"
    json_arr_v FIX "rename into a prefix: git branch -m $br ${FEATURE_PREFIX}$br" "or add a glob to doctor.ignoreBranches"
    fail_check branch-unrecognized info "branch '$br' matches no git-flow prefix" "\"branch\":\"$J\"" "$FIX" branch-unrecognized high "$br"
  done <<<"$LOCAL_LINES$NL$REMOTE_LINES"
  [ "$bu_found" = 0 ] && ok_check branch-unrecognized
fi

# --- A.7 GitHub-side ----------------------------------------------------------
GH_IDS="gh-protection-missing-main gh-protection-missing-develop gh-default-branch-unexpected gh-open-pr-wrong-base gh-squash-only-back-merge-limitation gh-release-missing-for-tag"
if [ "$GH_MODE" = 1 ]; then
  if [ "$PROT_MAIN" = false ]; then
    json_str_v J "$MAIN"
    json_arr_v FIX "enable protection (admin): gh api -X PUT repos/$SLUG/branches/$MAIN/protection ..."
    fail_check gh-protection-missing-main info "$MAIN has no branch protection on GitHub" "\"branch\":\"$J\"" "$FIX" gh-protection-missing-main
  elif [ -z "$PROT_MAIN" ]; then
    skip_check gh-protection-missing-main "api-error"
  else
    ok_check gh-protection-missing-main
  fi

  if [ "$PROT_DEV" = false ]; then
    json_str_v J "$DEVELOP"
    json_arr_v FIX "enable protection (admin): gh api -X PUT repos/$SLUG/branches/$DEVELOP/protection ..." "keep merge commits allowed so back-merges from $MAIN stay visible by ancestry"
    fail_check gh-protection-missing-develop info "$DEVELOP has no branch protection on GitHub" "\"branch\":\"$J\"" "$FIX" gh-protection-missing-develop
  elif [ -z "$PROT_DEV" ]; then
    skip_check gh-protection-missing-develop "api-error"
  else
    ok_check gh-protection-missing-develop
  fi

  if any_enabled gh-release-missing-for-tag; then
    if [ "$GITHUB_RELEASE" = 0 ]; then
      skip_check gh-release-missing-for-tag not-configured
    elif [ -z "$LATEST_TAG" ]; then
      skip_check gh-release-missing-for-tag no-semver-tags
    else
      REL_TAGS=""
      capture_all REL_TAGS gh release list --limit 500 --json tagName --jq '.[].tagName'
      rm_found=0
      while IFS= read -r t; do
        [ -z "$t" ] && continue
        is_semver_tag "$t" || continue
        glob_in_list "$t" "$IGNORE_TAGS" && continue
        case "$NL$REL_TAGS$NL" in *"$NL$t$NL"*) continue ;; esac
        rm_found=1
        json_str_v J "$t"
        json_arr_v FIX "gh release create $t --verify-tag --generate-notes --title $t" "or set release.githubRelease=false in .gitflow.json (--no-github-release)"
        fail_check gh-release-missing-for-tag info "tag $t (on $MAIN) has no GitHub Release" "\"tag\":\"$J\"" "$FIX" gh-release-missing-for-tag high "$t"
      done <<<"$MERGED_TAGS"
      [ "$rm_found" = 0 ] && ok_check gh-release-missing-for-tag
    fi
  fi

  if any_enabled gh-default-branch-unexpected; then
    DEFBRANCH=""
    capture DEFBRANCH gh repo view --json defaultBranchRef --jq .defaultBranchRef.name
    if [ -n "$DEFBRANCH" ] && [ "$DEFBRANCH" != "$DEVELOP" ]; then
      json_str_v J "$DEFBRANCH"
      json_arr_v FIX "gh repo edit --default-branch $DEVELOP"
      fail_check gh-default-branch-unexpected info "GitHub default branch is '$DEFBRANCH' (expected '$DEVELOP' so PRs target it by default)" \
        "\"defaultBranch\":\"$J\"" "$FIX" gh-default-branch-unexpected
    else
      ok_check gh-default-branch-unexpected
    fi
  fi

  if any_enabled gh-open-pr-wrong-base; then
    OPEN_PRS=""
    capture_all OPEN_PRS gh pr list --state open --json number,headRefName,baseRefName --jq '.[] | "\(.number) \(.headRefName) \(.baseRefName)"'
    wbpr_found=0
    while IFS=' ' read -r num phead pbase; do
      [ -z "$num" ] && continue
      case "$phead" in
        "$FEATURE_PREFIX"*)
          if [ "$pbase" = "$MAIN" ]; then
            wbpr_found=1
            json_str_v JH "$phead"; json_str_v JB "$pbase"
            json_arr_v FIX "gh pr edit $num --base $DEVELOP"
            fail_check gh-open-pr-wrong-base warning "PR #$num: $phead targets $MAIN instead of $DEVELOP" \
              "\"pr\":$num,\"head\":\"$JH\",\"base\":\"$JB\"" "$FIX" gh-open-pr-wrong-base high "$num"
          fi ;;
      esac
    done <<<"$OPEN_PRS"
    [ "$wbpr_found" = 0 ] && ok_check gh-open-pr-wrong-base
  fi

  if any_enabled gh-squash-only-back-merge-limitation; then
    MM=""
    capture MM gh repo view --json mergeCommitAllowed,squashMergeAllowed,rebaseMergeAllowed --jq '"\(.mergeCommitAllowed) \(.squashMergeAllowed) \(.rebaseMergeAllowed)"'
    merge_allowed=${MM%% *}
    if [ "$merge_allowed" = false ] && [ "$PROT_DEV" = true ]; then
      json_arr_v FIX "allow merge commits in repo settings" "or exempt $DEVELOP from protection for back-merges"
      fail_check gh-squash-only-back-merge-limitation info "merge commits disabled + $DEVELOP protected: $MAIN can never become an ancestor of $DEVELOP — doctor uses content-equivalence for back-merge checks" \
        "\"mergeCommitAllowed\":false,\"developProtected\":true" "$FIX" gh-squash-only-back-merge-limitation
    else
      ok_check gh-squash-only-back-merge-limitation
    fi
  fi
else
  for id in $GH_IDS; do skip_check "$id" "$GH_STATE"; done
fi

# --- A.8 distribution: Homebrew tap formula vs latest tag ------------------------
if any_enabled homebrew-formula-stale; then
  if ! homebrew_configured; then
    skip_check homebrew-formula-stale not-configured
  elif [ "$GH_MODE" != 1 ]; then
    skip_check homebrew-formula-stale "$GH_STATE"
  elif [ -z "$LATEST_TAG" ]; then
    skip_check homebrew-formula-stale no-semver-tags
  else
    HB_FORMULA=""
    tap_formula_v HB_FORMULA
    if [ -z "$HB_FORMULA" ]; then
      skip_check homebrew-formula-stale api-error
    elif formula_has_tag "$HB_FORMULA" "$LATEST_TAG"; then
      ok_check homebrew-formula-stale
    else
      hb_cur=""
      formula_tag_v hb_cur "$HB_FORMULA"
      json_str_v J "$HOMEBREW_TAP/$HOMEBREW_FORMULA"; json_str_v JT "$LATEST_TAG"; json_str_v JC "$hb_cur"
      json_arr_v FIX "resume: gitdoctor finish (homebrew-formula step) — or by hand per references/fix-recipes.md#homebrew-formula-stale" \
        "curl -sL https://github.com/$SLUG/archive/refs/tags/$LATEST_TAG.tar.gz | sha256sum"
      fail_check homebrew-formula-stale warning "Homebrew formula $HOMEBREW_FORMULA in $HOMEBREW_TAP ships ${hb_cur:-an unknown version} but the latest tag is $LATEST_TAG" \
        "\"formula\":\"$J\",\"formulaTag\":\"$JC\",\"latestTag\":\"$JT\"" "$FIX" homebrew-formula-stale high "$LATEST_TAG"
    fi
  fi
fi

finish_exit
