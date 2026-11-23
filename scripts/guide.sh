#!/usr/bin/env bash
# Lists the guide files of a repository: the files where a project keeps its
# rules for Claude Code. The skills read them before they write or review
# code, and name them to a companion plugin that would look in one place only.
# Runs in the current git working folder. Needs only git; no gh, no jq.
#
# Usage: guide.sh
#
# A guide file is one of these, in the repository's top folder or in any
# folder below it:
#   CLAUDE.md
#   .claude/CLAUDE.md
#   .claude/rules/<any path>.md
# Claude Code reads a project's guide from CLAUDE.md or from .claude/CLAUDE.md,
# so a repository may keep it in either place, or in both.
#
# It prints one path per file, from the repository's top folder, also when
# it is run from a subfolder, sorted, and then GUIDES=<n>. With no guide
# file it prints only GUIDES=0. Both end with exit code 0.
# A guide in the top folder (CLAUDE.md, .claude/CLAUDE.md or a file under
# .claude/rules/) holds rules for the whole repository. One in a subfolder
# holds rules for that subfolder.
# It lists the files that are in the folder now and that git tracks or
# would add: a file that git ignores is one person's own, and is left out.
# A path with a line break in its name is left out too.
# On failure it prints nothing on standard output and one "ERROR: ..." line
# on standard error, and exits 1.
set -euo pipefail

die() { echo "ERROR: $*" >&2; exit 1; }

case "${1:-}" in
  -h|--help|help)
    awk 'NR == 1 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "$0"
    exit 0 ;;
esac
[ $# -eq 0 ] || die "usage: guide.sh"

# git's own messages stay out of standard error: each failure is one ERROR line.
top="$(git rev-parse --show-toplevel 2>/dev/null)" || die "not inside a git working folder, so there is no repository to look for a guide in"
cd "$top" || die "couldn't open the folder $top"

# Without ":(glob)", a * in a git pattern also stands for folders, so
# "*/CLAUDE.md" finds the file at any depth. "*CLAUDE.md" would also find
# NOTCLAUDE.md, so the top folder has patterns of its own.
# -z: git prints each path as it is, with no quotes around an unusual name.
tracked_or_new() {
  git ls-files -z --cached --others --exclude-standard -- \
    'CLAUDE.md' '*/CLAUDE.md' '.claude/rules/*.md' '*/.claude/rules/*.md' 2>/dev/null
}
# One path per line, sorted, for the guide files that are there. Git matches
# the plain name CLAUDE.md to every file under a folder of that name too, so
# each path is checked again here. A file can be in git's list and gone from
# the folder. During a merge git lists a file once for each side, and it
# lists new files apart from tracked ones: so each path is put in its place
# among the ones before it, once. That is done with Bash itself, byte by
# byte: on Windows a `sort` on the PATH can be another program.
LC_ALL=C
existing() {
  local path i n=0 seen
  local -a sorted
  sorted=()
  while IFS= read -r -d '' path; do
    case "$path" in
      *$'\n'*) continue ;;
      CLAUDE.md|*/CLAUDE.md|.claude/rules/*.md|*/.claude/rules/*.md) ;;
      *) continue ;;
    esac
    [ -f "$path" ] || continue
    seen=0
    i=0
    while [ "$i" -lt "$n" ]; do
      if [ "${sorted[$i]}" = "$path" ]; then seen=1; fi
      i=$((i + 1))
    done
    [ "$seen" = 0 ] || continue
    i=$n
    while [ "$i" -gt 0 ] && [[ "${sorted[$((i - 1))]}" > "$path" ]]; do
      sorted[$i]="${sorted[$((i - 1))]}"
      i=$((i - 1))
    done
    sorted[$i]="$path"
    n=$((n + 1))
  done
  i=0
  while [ "$i" -lt "$n" ]; do
    printf '%s\n' "${sorted[$i]}"
    i=$((i + 1))
  done
}

# The function reads git's list to its end, so pipefail gives the same
# answer on every run.
list="$(tracked_or_new | existing)" || die "couldn't list the repository's files with git"

count=0
if [ -n "$list" ]; then
  printf '%s\n' "$list"
  while IFS= read -r _; do count=$((count + 1)); done <<<"$list"
fi
echo "GUIDES=$count"
