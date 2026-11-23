#!/usr/bin/env bash
# Runs scripts/guide.sh in real git repositories, made in a temporary folder,
# and checks which guide files it lists, what it prints and how it exits.
# Then checks this repository's own guide: it is in .claude/CLAUDE.md and not
# in the top folder, and .gitignore keeps a person's own Claude Code files
# out of git without ignoring the guide.
# Needs git, and no GitHub and no jq.
# Run: bash tests/guide/run.sh
set -euo pipefail
command -v git > /dev/null 2>&1 || { echo "FAIL: this test needs git, and git is not installed"; exit 1; }
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../.." && pwd)"
# The real path of the temporary folder: on macOS /tmp is a link.
tmp="$(cd "$(mktemp -d)" && pwd -P)"
errf="$tmp/standard-error"
trap 'rm -rf "$tmp"' EXIT
# Cut git off from the settings of the user and of the system: an ignore
# file of their own could already list a guide file. And keep git from
# looking for a repository above the temporary folder.
mkdir "$tmp/home"
export HOME="$tmp/home" XDG_CONFIG_HOME="$tmp/home/config" GIT_CONFIG_NOSYSTEM=1
export GIT_CEILING_DIRECTORIES="$tmp"
unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_INDEX_FILE
# The files keep the line endings they are written with, so git has nothing
# to say about them on Windows.
git config --global core.autocrlf false
fail=0; passed=0

# Runs guide.sh in a folder. Sets `out` (standard output), `err` (standard
# error) and `code` (the exit code).
run_in() { # run_in <folder> [arguments]
  local folder="$1"; shift
  set +e
  out="$(cd "$folder" && bash "$root/scripts/guide.sh" ${1+"$@"} 2>"$errf")"; code=$?
  set -e
  err="$(cat "$errf")"
}
# check <what is checked> <got> <wanted>
check() {
  if [ "$2" = "$3" ]; then
    passed=$((passed + 1))
  else
    echo "FAIL: $1"
    diff <(printf '%s\n' "$3") <(printf '%s\n' "$2") | sed 's/^/  /' || true
    fail=1
  fi
}
yes_no() { if "$@" > /dev/null 2>&1; then echo yes; else echo no; fi; }
# like <text> <pattern>: says "as wanted" when the text fits the pattern, and
# gives the text back when it does not, so that a failed check shows it. No
# case is written inside $(...): Bash 3.2 can't read one there.
like() {
  # shellcheck disable=SC2254
  case "$1" in
    $2) echo "as wanted" ;;
    *) printf '%s\n' "$1" ;;
  esac
}
# commit <repository> <arguments of git commit>
commit() {
  local folder="$1"; shift
  git -C "$folder" -c user.name=test -c user.email=test@example.com commit -q "$@"
}
# Makes a repository with one commit. Sets `repo`.
new_repo() { # new_repo <name>
  repo="$tmp/$1"
  git init -q "$repo" > /dev/null 2>&1
  commit "$repo" --allow-empty -m first
}
# Makes a file with one line, and the folders above it.
put() { # put <repository> <path>
  mkdir -p "$(dirname "$1/$2")"
  echo "rules" > "$1/$2"
}
# listed <what> <the standard output wanted>: the run printed that, nothing
# on standard error, and exited 0.
listed() {
  check "$1: standard output" "$out" "$2"
  check "$1: standard error" "$err" ""
  check "$1: exit code" "$code" 0
}
# stopped <what> <the ERROR line wanted>
stopped() {
  check "$1: standard output is empty" "$out" ""
  check "$1: standard error" "$err" "$2"
  check "$1: exit code" "$code" 1
}

# A repository with no guide.
new_repo none
put "$repo" README.md
run_in "$repo"
listed "no guide" "GUIDES=0"

# The guide is CLAUDE.md in the top folder.
new_repo top
put "$repo" CLAUDE.md
git -C "$repo" add CLAUDE.md
commit "$repo" -m guide
run_in "$repo"
listed "CLAUDE.md in the top folder" "CLAUDE.md
GUIDES=1"

# The guide is .claude/CLAUDE.md, and nothing is in the top folder. A look
# for "the root CLAUDE.md" misses this one.
new_repo dot-claude
put "$repo" .claude/CLAUDE.md
git -C "$repo" add .claude/CLAUDE.md
commit "$repo" -m guide
run_in "$repo"
listed ".claude/CLAUDE.md alone" ".claude/CLAUDE.md
GUIDES=1"

# Both places, rules files, and guides of subfolders, among files that only
# look like one. The list is sorted byte by byte.
new_repo many
for path in CLAUDE.md .claude/CLAUDE.md .claude/rules/style.md .claude/rules/api/errors.md \
  packages/api/CLAUDE.md packages/web/.claude/CLAUDE.md packages/web/.claude/rules/css.md \
  "my docs/CLAUDE.md"; do
  put "$repo" "$path"
done
for path in NOTCLAUDE.md docs/MYCLAUDE.md CLAUDE.md.bak .claude/settings.json .claude/rules/notes.txt \
  rules/style.md .claude/commands/ship.md packages/api/README.md; do
  put "$repo" "$path"
done
git -C "$repo" add -A
commit "$repo" -m guides
many=".claude/CLAUDE.md
.claude/rules/api/errors.md
.claude/rules/style.md
CLAUDE.md
my docs/CLAUDE.md
packages/api/CLAUDE.md
packages/web/.claude/CLAUDE.md
packages/web/.claude/rules/css.md
GUIDES=8"
run_in "$repo"
listed "guides in many places" "$many"

# A second run prints the same.
run_in "$repo"
listed "second run" "$many"

# From a subfolder, the paths still start at the top folder, and guides
# outside the subfolder are still listed.
run_in "$repo/packages/api"
listed "run from a subfolder" "$many"

# A folder named CLAUDE.md is not a guide file, in the top folder or below
# it, and a file inside it is not one either. Git matches a plain name to
# everything under a folder of that name, so the script checks each path.
new_repo folder
put "$repo" CLAUDE.md/inside.md
put "$repo" docs/CLAUDE.md/inside.md
put "$repo" .claude/rules/README
git -C "$repo" add -A
commit "$repo" -m folder
run_in "$repo"
listed "a folder named CLAUDE.md" "GUIDES=0"

# A new file that is not committed yet is listed: it is in the folder, and
# git would add it.
new_repo new-file
put "$repo" .claude/CLAUDE.md
run_in "$repo"
listed "a guide that is not committed yet" ".claude/CLAUDE.md
GUIDES=1"

# Git lists new files apart from committed ones. The list is still one,
# sorted byte by byte, so a capital letter comes before a small one.
new_repo mixed
put "$repo" CLAUDE.md
put "$repo" m/CLAUDE.md
git -C "$repo" add -A
commit "$repo" -m guides
put "$repo" .claude/CLAUDE.md
put "$repo" a/CLAUDE.md
put "$repo" z/CLAUDE.md
put "$repo" Docs/.claude/rules/one.md
run_in "$repo"
listed "new and committed guides together" ".claude/CLAUDE.md
CLAUDE.md
Docs/.claude/rules/one.md
a/CLAUDE.md
m/CLAUDE.md
z/CLAUDE.md
GUIDES=6"

# A file that git ignores is one person's own: it is left out. A guide that
# is in a commit stays listed, also when a rule would ignore it.
new_repo ignored
put "$repo" CLAUDE.md
put "$repo" kept/CLAUDE.md
git -C "$repo" add -A
commit "$repo" -m guides
printf 'scratch/\nkept/\n' > "$repo/.gitignore"
put "$repo" scratch/CLAUDE.md
run_in "$repo"
listed "an ignored guide" "CLAUDE.md
kept/CLAUDE.md
GUIDES=2"

# A guide that git still lists, and that is gone from the folder, is left out.
new_repo deleted
put "$repo" CLAUDE.md
put "$repo" .claude/CLAUDE.md
git -C "$repo" add -A
commit "$repo" -m guides
rm "$repo/CLAUDE.md"
run_in "$repo"
listed "a guide deleted from the folder" ".claude/CLAUDE.md
GUIDES=1"

# A guide moved with git mv and not committed yet: only the new place.
new_repo moved
put "$repo" CLAUDE.md
git -C "$repo" add -A
commit "$repo" -m guide
mkdir "$repo/.claude"
git -C "$repo" mv CLAUDE.md .claude/CLAUDE.md
run_in "$repo"
listed "a guide moved and not committed" ".claude/CLAUDE.md
GUIDES=1"

# During a merge that stopped on the guide, git lists the file once for
# each side. It is printed once.
new_repo conflict
put "$repo" CLAUDE.md
git -C "$repo" add -A
commit "$repo" -m guide
first="$(git -C "$repo" rev-parse --abbrev-ref HEAD)"
git -C "$repo" checkout -q -b other
echo "rules of the other branch" > "$repo/CLAUDE.md"
commit "$repo" -a -m other
git -C "$repo" checkout -q "$first"
echo "rules of the first branch" > "$repo/CLAUDE.md"
commit "$repo" -a -m mine
check "the merge stops on the guide" "$(yes_no git -C "$repo" -c user.name=test -c user.email=test@example.com merge -q other)" no
stages="$(git -C "$repo" ls-files -s -- CLAUDE.md | wc -l | tr -d ' ')"
check "git lists the guide more than once" "$(yes_no test "$stages" -gt 1)" yes
run_in "$repo"
listed "a guide in a stopped merge" "CLAUDE.md
GUIDES=1"

# Git can't read its own list of files: one ERROR line, and no list that
# could pass for "no guide".
new_repo broken
put "$repo" CLAUDE.md
git -C "$repo" add -A
commit "$repo" -m guide
printf 'not an index' > "$repo/.git/index"
run_in "$repo"
stopped "git can't list the files" "ERROR: couldn't list the repository's files with git"

# Outside a git repository.
mkdir "$tmp/plain"
put "$tmp/plain" CLAUDE.md
run_in "$tmp/plain"
stopped "outside a repository" "ERROR: not inside a git working folder, so there is no repository to look for a guide in"

# It takes no arguments.
run_in "$tmp/top" somewhere
stopped "an argument" "ERROR: usage: guide.sh"
run_in "$tmp/top" help
check "help: prints what the script does" "$(like "$out" "*GUIDES=<n>*")" "as wanted"
check "help: exit code" "$code" 0

# This repository's own guide. Its top folder is also the plugin's root, and
# `claude plugin validate . --strict` fails on a CLAUDE.md there. These
# checks read files only, so they also run in a copy that is not a git
# repository.
check "this repository: the guide is in .claude/CLAUDE.md" "$(yes_no test -f "$root/.claude/CLAUDE.md")" yes
check "this repository: no CLAUDE.md in the top folder" "$(yes_no test -e "$root/CLAUDE.md")" no

# This repository's .gitignore, tried in a new repository so that git's own
# exclude file here plays no part.
new_repo own-gitignore
cp "$root/.gitignore" "$repo/.gitignore"
ignored() { git -C "$repo" check-ignore -q --no-index "$1"; }
for path in .claude/settings.local.json .claude/CLAUDE.local.md CLAUDE.local.md \
  .claude.local.md docs/.claude.local.md \
  .claude/worktrees/one/README.md .claude/agent-memory-local/reviewer/MEMORY.md \
  .claude/scheduled_tasks.json; do
  check ".gitignore: $path stays out of git" "$(yes_no ignored "$path")" yes
done
for path in .claude/CLAUDE.md .claude/settings.json .claude/rules/style.md CLAUDE.md README.md; do
  check ".gitignore: $path is not ignored" "$(yes_no ignored "$path")" no
done
put "$repo" .claude/CLAUDE.md
run_in "$repo"
listed "with this repository's .gitignore, the guide is still found" ".claude/CLAUDE.md
GUIDES=1"

[ "$fail" = 0 ] && echo "PASS: $passed checks"
exit "$fail"
