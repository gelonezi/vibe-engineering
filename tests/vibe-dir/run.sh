#!/usr/bin/env bash
# Runs scripts/vibe-dir.sh in real git repositories, made in a temporary
# folder, and checks the folder it makes, what it leaves in git's exclude
# file, what it prints and how it exits. Needs git, and no GitHub and no jq.
# Run: bash tests/vibe-dir/run.sh
set -euo pipefail
command -v git > /dev/null 2>&1 || { echo "FAIL: this test needs git, and git is not installed"; exit 1; }
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../.." && pwd)"
# The real path of the temporary folder: on macOS /tmp is a link.
tmp="$(cd "$(mktemp -d)" && pwd -P)"
errf="$tmp/standard-error"
trap 'rm -rf "$tmp"' EXIT
# Cut git off from the settings of the user and of the system: an ignore
# file of their own could already list .vibe. And keep git from looking for
# a repository above the temporary folder.
mkdir "$tmp/home"
export HOME="$tmp/home" XDG_CONFIG_HOME="$tmp/home/config" GIT_CONFIG_NOSYSTEM=1
export GIT_CEILING_DIRECTORIES="$tmp"
unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_INDEX_FILE
fail=0; passed=0

# Runs vibe-dir.sh in a folder. Sets `out` (standard output), `err`
# (standard error) and `code` (the exit code).
run_in() { # run_in <folder> [arguments]
  local folder="$1"; shift
  set +e
  out="$(cd "$folder" && bash "$root/scripts/vibe-dir.sh" ${1+"$@"} 2>"$errf")"; code=$?
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
# A file's bytes on one line, with \n for a line break and \r for a carriage
# return, so that a missing or an extra line break shows. The fixtures hold
# no spaces, because od puts spaces between the bytes.
bytes() { od -An -c "$1" | tr -d ' \n'; }
# How many lines a text has. An empty text has none.
lines() { if [ -z "$1" ]; then echo 0; else printf '%s\n' "$1" | wc -l | tr -d ' '; fi; }
# Makes a repository with one commit. Sets `repo` and `exclude`.
new_repo() { # new_repo <name>
  repo="$tmp/$1"
  git init -q "$repo" > /dev/null 2>&1
  git -C "$repo" -c user.name=test -c user.email=test@example.com commit -q --allow-empty -m first
  exclude="$repo/.git/info/exclude"
}
ignored() { git -C "$1" check-ignore -q "$2"; } # ignored <repository> <path>
# like <text> <pattern>: says "as wanted" when the text fits the pattern, and
# gives the text back when it does not, so that a failed check shows it. A *
# in the pattern stands for a path, which differs from one system to the
# next. No case is written inside $(...): Bash 3.2 can't read one there.
like() {
  # shellcheck disable=SC2254
  case "$1" in
    $2) echo "as wanted" ;;
    *) printf '%s\n' "$1" ;;
  esac
}
# worked <what>: the run printed one VIBE_DIR= line, nothing on standard
# error, and exited 0.
worked() {
  check "$1: standard output names the folder" "$(like "$out" "VIBE_DIR=*/.vibe")" "as wanted"
  check "$1: standard output is one line" "$(lines "$out")" 1
  check "$1: standard error" "$err" ""
  check "$1: exit code" "$code" 0
}
# stopped <what> <the ERROR line wanted>
stopped() {
  check "$1: standard output is empty" "$out" ""
  check "$1: standard error" "$(like "$err" "$2")" "as wanted"
  check "$1: standard error is one line" "$(lines "$err")" 1
  check "$1: exit code" "$code" 1
}

# The exclude file is missing, and so is its folder.
new_repo missing
rm -rf "$repo/.git/info"
run_in "$repo"
worked "no exclude file"
check "no exclude file: the folder is made" "$(yes_no test -d "$repo/.vibe")" yes
check "no exclude file: the file holds the pattern" "$(bytes "$exclude")" '.vibe/\n'
check "no exclude file: git ignores .vibe" "$(yes_no ignored "$repo" .vibe/x)" yes
# The path it prints is the folder in the repository's top folder.
dir="${out#VIBE_DIR=}"
check "the path printed is a folder" "$(yes_no test -d "$dir")" yes
: > "$dir/probe"
check "a file written there is under the top folder's .vibe" "$(yes_no test -f "$repo/.vibe/probe")" yes
check "git status shows nothing of it" "$(git -C "$repo" status --porcelain)" ""

# The exclude file is empty.
new_repo empty
: > "$exclude"
run_in "$repo"
worked "empty exclude file"
check "empty exclude file: the file holds the pattern" "$(bytes "$exclude")" '.vibe/\n'

# The exclude file ends with a line break: no empty line is added.
new_repo ends-with-break
printf '#note\nfoo\n' > "$exclude"
run_in "$repo"
worked "exclude file that ends with a line break"
check "exclude file that ends with a line break: the pattern is the new last line" "$(bytes "$exclude")" '#note\nfoo\n.vibe/\n'

# The last line has no line break: the pattern still gets a line of its
# own, and the pattern before it keeps working.
new_repo no-break
printf 'foo' > "$exclude"
run_in "$repo"
worked "exclude file without a line break at its end"
check "exclude file without a line break at its end: each pattern on its own line" "$(bytes "$exclude")" 'foo\n.vibe/\n'
check "exclude file without a line break at its end: git ignores .vibe" "$(yes_no ignored "$repo" .vibe/x)" yes
check "exclude file without a line break at its end: git still ignores foo" "$(yes_no ignored "$repo" foo)" yes

# A second run changes nothing.
cp "$exclude" "$tmp/before"
run_in "$repo"
worked "second run"
check "second run: the exclude file is the same" "$(yes_no cmp -s "$exclude" "$tmp/before")" yes

# The pattern is already there, in a file with carriage returns.
new_repo windows
printf 'foo\r\n.vibe/\r\n' > "$exclude"
run_in "$repo"
worked "exclude file with carriage returns"
check "exclude file with carriage returns: nothing is added" "$(bytes "$exclude")" 'foo\r\n.vibe/\r\n'

# The repository's own .gitignore already ignores the folder.
new_repo gitignore
printf '.vibe\n' > "$repo/.gitignore"
cp "$exclude" "$tmp/before"
run_in "$repo"
worked ".vibe in .gitignore"
check ".vibe in .gitignore: the exclude file is not changed" "$(yes_no cmp -s "$exclude" "$tmp/before")" yes

# A file under .vibe is already in a commit. That is where the glued pattern
# led: the hand-over file showed in git status, and it was committed. Git is
# asked about a new file, so the committed one does not stop the run, and a
# new file stays out of git status.
new_repo committed
mkdir "$repo/.vibe"
: > "$repo/.vibe/fixed-threads-7.txt"
git -C "$repo" add -f .vibe/fixed-threads-7.txt > /dev/null 2>&1
git -C "$repo" -c user.name=test -c user.email=test@example.com commit -q -m second
printf 'foo' > "$exclude"
run_in "$repo"
worked "a committed file under .vibe"
check "a committed file under .vibe: the pattern is added" "$(bytes "$exclude")" 'foo\n.vibe/\n'
: > "$repo/.vibe/review-1.md"
check "a committed file under .vibe: git ignores a new file" "$(yes_no ignored "$repo" .vibe/review-1.md)" yes
check "a committed file under .vibe: git status shows nothing of the new file" "$(git -C "$repo" status --porcelain)" ""
# The pattern is there now, and the committed file still is: nothing is added.
cp "$exclude" "$tmp/before"
run_in "$repo"
worked "a committed file under .vibe, second run"
check "a committed file under .vibe, second run: the exclude file is the same" "$(yes_no cmp -s "$exclude" "$tmp/before")" yes
# push deletes the hand-over file from the working folder only: it is still
# in git's index.
rm "$repo/.vibe/fixed-threads-7.txt"
run_in "$repo"
worked "a committed file under .vibe, deleted from the folder"
check "a committed file under .vibe, deleted from the folder: the exclude file is the same" "$(yes_no cmp -s "$exclude" "$tmp/before")" yes
# A rule that un-ignores the folder still stops the run there.
printf '!.vibe/\n' > "$repo/.gitignore"
run_in "$repo"
stopped "a committed file under .vibe and a rule that un-ignores it" "ERROR: git still does not ignore .vibe/ after adding it to *: look for a rule such as !.vibe in a .gitignore"

# From a subfolder, the folder is still made in the top folder.
new_repo subfolder
mkdir -p "$repo/a/b"
run_in "$repo/a/b"
worked "from a subfolder"
check "from a subfolder: the folder is in the top folder" "$(yes_no test -d "$repo/.vibe")" yes
check "from a subfolder: no folder in the subfolder" "$(yes_no test -e "$repo/a/b/.vibe")" no
check "from a subfolder: git ignores .vibe" "$(yes_no ignored "$repo" .vibe/x)" yes

# A linked worktree: its .git is a file, and the exclude file is the main
# repository's.
new_repo main
printf 'foo' > "$exclude"
git -C "$repo" worktree add -q -b other "$tmp/linked" > /dev/null 2>&1
check "linked worktree: .git is a file there" "$(yes_no test -f "$tmp/linked/.git")" yes
run_in "$tmp/linked"
worked "linked worktree"
check "linked worktree: the folder is in the worktree" "$(yes_no test -d "$tmp/linked/.vibe")" yes
check "linked worktree: no folder in the main repository" "$(yes_no test -e "$repo/.vibe")" no
check "linked worktree: the pattern is in the main repository's exclude file" "$(bytes "$exclude")" 'foo\n.vibe/\n'
: > "$tmp/linked/.vibe/fixed-threads-7.txt"
check "linked worktree: git status shows nothing" "$(git -C "$tmp/linked" status --porcelain)" ""

# A rule that tells git not to ignore the folder wins over the exclude
# file. The files would show in git status, so this is a failure. A second
# run adds no second line.
new_repo unignored
printf '!.vibe/\n' > "$repo/.gitignore"
: > "$exclude"
run_in "$repo"
stopped "a rule that un-ignores .vibe" "ERROR: git still does not ignore .vibe/ after adding it to *: look for a rule such as !.vibe in a .gitignore"
run_in "$repo"
stopped "a rule that un-ignores .vibe, second run" "ERROR: git still does not ignore .vibe/ after adding it to *: look for a rule such as !.vibe in a .gitignore"
check "a rule that un-ignores .vibe: the pattern is added once" "$(bytes "$exclude")" '.vibe/\n'

# .vibe is there as a file, so the folder can't be made.
new_repo blocked
: > "$repo/.vibe"
run_in "$repo"
stopped ".vibe is a file" "ERROR: couldn't create the folder */.vibe"

# The exclude file can't be written: a folder is in its place.
new_repo unwritable
rm -f "$exclude"
mkdir "$exclude"
run_in "$repo"
stopped "the exclude file can't be written" "ERROR: couldn't write to git's exclude file: *"

# Outside a git repository.
mkdir "$tmp/plain"
run_in "$tmp/plain"
stopped "outside a repository" "ERROR: not inside a git working folder, so there is no place for .vibe"
check "outside a repository: no folder is made" "$(yes_no test -e "$tmp/plain/.vibe")" no

# It takes no arguments.
new_repo arguments
run_in "$repo" somewhere
stopped "an argument" "ERROR: usage: vibe-dir.sh"
check "an argument: no folder is made" "$(yes_no test -e "$repo/.vibe")" no
run_in "$repo" help
check "help: prints what the script does" "$(like "$out" "*VIBE_DIR=*")" "as wanted"
check "help: exit code" "$code" 0
check "help: no folder is made" "$(yes_no test -e "$repo/.vibe")" no

[ "$fail" = 0 ] && echo "PASS: $passed checks"
exit "$fail"
