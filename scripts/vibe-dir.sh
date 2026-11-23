#!/usr/bin/env bash
# Makes the .vibe folder, where the review and develop skills keep the files
# that must never be committed, and makes sure git ignores it.
# Runs in the current git working folder. Needs only git; no gh, no jq.
#
# Usage: vibe-dir.sh
#
# It makes .vibe in the top folder of the working folder, also when it is
# run from a subfolder, and prints VIBE_DIR=<path>, the folder's full path.
# When git does not ignore .vibe/ yet, it adds the line ".vibe/" to git's own
# exclude file, which is never committed. Git names that file, because in a
# git worktree or a submodule .git is a file, not a folder. The pattern goes
# on a line of its own, also when the file's last line has no line break.
# When git already ignores the folder, by any rule in any file, nothing is
# added, so it is safe to run again.
# Git is asked whether a new file there would be ignored. A file under .vibe
# that is already in a commit stays tracked, and does not change the answer.
# On failure it prints nothing on standard output and one "ERROR: ..." line
# on standard error, and exits 1.
set -euo pipefail

die() { echo "ERROR: $*" >&2; exit 1; }

case "${1:-}" in
  -h|--help|help)
    awk 'NR == 1 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "$0"
    exit 0 ;;
esac
[ $# -eq 0 ] || die "usage: vibe-dir.sh"

# git's own messages stay out of standard error: each failure is one ERROR line.
top="$(git rev-parse --show-toplevel 2>/dev/null)" || die "not inside a git working folder, so there is no place for .vibe"
cd "$top" || die "couldn't open the folder $top"
mkdir -p .vibe 2>/dev/null || die "couldn't create the folder $top/.vibe"

# --no-index: the answer comes from the ignore rules alone. Without it, one
# file under .vibe in git's index makes git answer "not ignored", although a
# new file there is ignored.
ignored() { git check-ignore -q --no-index .vibe/ 2>/dev/null; }

if ! ignored; then
  # Asked from the top folder, so a path that is not absolute starts there.
  exclude="$(git rev-parse --git-path info/exclude 2>/dev/null)" || die "git gave no path for its exclude file"
  # The same line is not added twice, also when another rule keeps it from working.
  if ! grep -qxF '.vibe/' "$exclude" 2>/dev/null; then
    case "$exclude" in */*) mkdir -p "${exclude%/*}" 2>/dev/null || true ;; esac
    # A last line without a line break would be glued to the pattern: end it
    # first. $(...) drops a line break, so the text is empty when the last
    # character is one.
    # Standard error is turned away before the file is opened, so that a
    # file that can't be written gives the one ERROR line and nothing else.
    {
      if [ -s "$exclude" ] && [ -n "$(tail -c 1 "$exclude")" ]; then echo; fi
      echo '.vibe/'
    } 2>/dev/null >> "$exclude" || die "couldn't write to git's exclude file: $exclude"
  fi
  ignored || die "git still does not ignore .vibe/ after adding it to $exclude: look for a rule such as !.vibe in a .gitignore"
fi

echo "VIBE_DIR=$top/.vibe"
