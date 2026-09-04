#!/usr/bin/env bash
# Installs the GitFlow skill for Claude Code (user-level) and optionally the
# Cursor command adapter into a target repo.
#
#   ./install.sh                      # Claude Code only (~/.claude/skills/gitdoctor)
#   ./install.sh --cursor-repo /path  # + .cursor/commands/gitdoctor.md in that repo
set -eu

SRC=$(cd "$(dirname "$0")" && pwd)
CURSOR_REPO=""
while [ $# -gt 0 ]; do
  case "$1" in
    --cursor-repo) CURSOR_REPO=${2:?}; shift 2 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done

SKILL_DIR="$HOME/.claude/skills/gitdoctor"
mkdir -p "$SKILL_DIR"
cp "$SRC/SKILL.md" "$SKILL_DIR/"
rm -rf "$SKILL_DIR/references" "$SKILL_DIR/scripts"
cp -R "$SRC/references" "$SRC/scripts" "$SKILL_DIR/"
echo "Claude Code skill installed: $SKILL_DIR"

if [ -n "$CURSOR_REPO" ]; then
  [ -d "$CURSOR_REPO" ] || { echo "cursor repo not found: $CURSOR_REPO" >&2; exit 1; }
  CMD_DIR="$CURSOR_REPO/.cursor/commands"
  mkdir -p "$CMD_DIR/gitdoctor-skill"
  cp "$SRC/adapters/cursor/gitdoctor.md" "$CMD_DIR/gitdoctor.md"
  cp "$SRC/SKILL.md" "$CMD_DIR/gitdoctor-skill/"
  rm -rf "$CMD_DIR/gitdoctor-skill/references" "$CMD_DIR/gitdoctor-skill/scripts"
  cp -R "$SRC/references" "$SRC/scripts" "$CMD_DIR/gitdoctor-skill/"
  echo "Cursor command installed: $CMD_DIR/gitdoctor.md (+ gitdoctor-skill payload)"
fi
