#!/usr/bin/env bash
# Opens the help page in the user's default browser and prints its path.
# Usage: open-help.sh [--print]     --print only prints the path
set -uo pipefail

dir="$(cd "$(dirname "$0")/../assets" && pwd)"
page="$dir/help.html"
[ -f "$page" ] || { echo "ERROR: help page not found: $page" >&2; exit 1; }

os="$(uname -s)"
case "$os" in
  MINGW*|MSYS*|CYGWIN*) shown="$(cygpath -w "$page" 2>/dev/null || printf '%s' "$page")" ;;
  *) shown="$page" ;;
esac
echo "PAGE=$shown"
[ "${1:-}" = "--print" ] && exit 0

opened=false
case "$os" in
  MINGW*|MSYS*|CYGWIN*)
    # MSYS_NO_PATHCONV keeps Git Bash from turning /c into a Windows path.
    MSYS_NO_PATHCONV=1 cmd.exe /c start "" "$shown" && opened=true ;;
  Darwin)
    open "$page" && opened=true ;;
  Linux)
    if grep -qi microsoft /proc/version 2>/dev/null && command -v wslview >/dev/null 2>&1; then
      wslview "$page" && opened=true
    elif command -v xdg-open >/dev/null 2>&1; then
      xdg-open "$page" >/dev/null 2>&1 && opened=true
    fi ;;
esac
echo "OPENED=$opened"
