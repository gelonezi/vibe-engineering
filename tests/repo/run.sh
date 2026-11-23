#!/usr/bin/env bash
# Runs the review thread commands of scripts/repo.sh (pr-threads, pr-comments
# and resolve-thread) and its pr-edit against a stand-in gh, and checks what
# they print on standard output and on standard error, and how they exit. It
# also checks that repo.sh and next.sh read the same end of a pull request's
# list of review threads. Needs jq (1.7 or newer on Windows), and no GitHub.
# Run: bash tests/repo/run.sh
set -euo pipefail
command -v jq > /dev/null 2>&1 || { echo "FAIL: this test needs jq, and jq is not installed"; exit 1; }
# A jq built for Windows ends each line with a carriage return, which the
# real gh --jq does not. jq's binary mode (-b, in jq 1.7 and newer) stops
# that. The stand-in gh passes $GH_STUB_JQ to jq: -b where this jq needs it,
# and nothing anywhere else, so an older jq still works there. The bytes are
# counted, "1" and a line break being two, because Git Bash drops a carriage
# return at the end of a $(...).
export GH_STUB_JQ=""
if [ "$(jq -n 1 | wc -c | tr -d ' ')" = 3 ]; then
  [ "$(jq -b -n 1 2> /dev/null | wc -c | tr -d ' ')" = 2 ] || { echo "FAIL: this jq ends each line with a carriage return and has no binary mode (-b) to stop that: here the test needs jq 1.7 or newer"; exit 1; }
  GH_STUB_JQ=-b
fi
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../.." && pwd)"
export GH_STUB_LOG; GH_STUB_LOG="$(mktemp)"
errf="$(mktemp)"
nomktemp="$(mktemp -d)"
# Where the stand-in gh keeps what "pr edit" was given, and the files pr-edit
# reads its title and description from.
export GH_STUB_SENT; GH_STUB_SENT="$(mktemp -d)"
texts="$(mktemp -d)"
trap 'rm -rf "$GH_STUB_LOG" "$errf" "$nomktemp" "$GH_STUB_SENT" "$texts"' EXIT
fail=0; passed=0

# Runs repo.sh with the stand-in gh. Sets `out` (standard output), `err`
# (standard error) and `code` (the exit code). A folder in `first` goes
# before everything else in PATH.
run() {
  set +e
  out="$(PATH="${first:+$first:}$here:$PATH" bash "$root/scripts/repo.sh" "$@" 2>"$errf")"; code=$?
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
# How many lines a text has. An empty text has none.
lines() { if [ -z "$1" ]; then echo 0; else printf '%s\n' "$1" | wc -l | tr -d ' '; fi; }

# pr-threads and pr-comments. Pull request 7 has four threads and all four
# are read. Pull request 8 has more threads than are read. The stand-in gh
# fails a query that does not ask for reviewThreads(last: 100).
for command in threads comments; do
  for number in 7 8; do
    run "pr-$command" "$number"
    check "pr-$command $number: standard output" "$out" "$(cat "$here/$command-$number.tsv")"
    check "pr-$command $number: standard error" "$err" ""
    check "pr-$command $number: exit code" "$code" 0
  done
done

# Both scripts must read the same end of the list: the Fix comments button
# follows the threads next.sh reads, and push resolves the ones pr-threads
# lists.
found="$(grep -o 'reviewThreads([^)]*)' "$root/scripts/repo.sh" "$root/scripts/next.sh" || true)"
# Two places in repo.sh and one in next.sh, at least: an empty list would
# make the check below pass without checking anything.
check "repo.sh and next.sh read review threads in at least three places" \
  "$([ "$(lines "$found")" -ge 3 ] && echo yes || echo no)" yes
check "every reviewThreads(...) in repo.sh and next.sh is reviewThreads(last: 100)" \
  "$(printf '%s\n' "$found" | grep -v ':reviewThreads(last: 100)$' || true)" ""

# resolve-thread, when GitHub resolves the thread.
run resolve-thread PRRT_ok
check "resolve-thread, resolved: standard output" "$out" "RESOLVED=true"
check "resolve-thread, resolved: standard error" "$err" ""
check "resolve-thread, resolved: exit code" "$code" 0

# resolve-thread, when it fails: nothing on standard output, one ERROR line
# on standard error with gh's message, and exit 1.
failed() { # failed <thread id> <the ERROR line wanted>
  run resolve-thread "$1"
  check "resolve-thread $1: standard output is empty" "$out" ""
  check "resolve-thread $1: standard error" "$err" "$2"
  check "resolve-thread $1: exit code" "$code" 1
}
failed PRRT_missing "ERROR: couldn't resolve thread PRRT_missing: Could not resolve to a node with the global id of 'PRRT_missing'"
failed PRRT_forbidden "ERROR: couldn't resolve thread PRRT_forbidden: me does not have the correct permissions to execute \`ResolveReviewThread\`"
failed PRRT_offline "ERROR: couldn't resolve thread PRRT_offline: error connecting to api.github.com check your internet connection or https://githubstatus.com"
failed PRRT_silent "ERROR: couldn't resolve thread PRRT_silent: GitHub gave no reason"
failed PRRT_stuck "ERROR: GitHub did not mark thread PRRT_stuck as resolved"
# gh on Windows ends its message with a carriage return and a line break. The
# ERROR line must not carry the carriage return.
failed PRRT_windows "ERROR: couldn't resolve thread PRRT_windows: Could not resolve to a node with the global id of 'PRRT_windows'"

# resolve-thread when the temporary file can't be made: mktemp's own message
# stays out of standard error, and GitHub is not called. A stand-in mktemp
# that always fails is put first in PATH for this one run.
calls="$(wc -l < "$GH_STUB_LOG" | tr -d ' ')"
printf '%s\n' '#!/usr/bin/env bash' 'echo "mktemp: failed to create file" >&2' 'exit 1' > "$nomktemp/mktemp"
chmod +x "$nomktemp/mktemp"
first="$nomktemp" run resolve-thread PRRT_ok
check "resolve-thread without a temporary file: standard output is empty" "$out" ""
check "resolve-thread without a temporary file: standard error" "$err" "ERROR: couldn't create a temporary file, so nothing was resolved"
check "resolve-thread without a temporary file: exit code" "$code" 1
check "resolve-thread without a temporary file: gh is not called" "$(wc -l < "$GH_STUB_LOG" | tr -d ' ')" "$calls"

# resolve-thread with an empty id or no id stops before it calls GitHub.
calls="$(wc -l < "$GH_STUB_LOG" | tr -d ' ')"
run resolve-thread ""
check "resolve-thread with an empty id: standard output is empty" "$out" ""
check "resolve-thread with an empty id: standard error" "$err" "ERROR: usage: resolve-thread <threadId>"
check "resolve-thread with an empty id: exit code" "$code" 1
run resolve-thread
check "resolve-thread with no id: standard error" "$err" "ERROR: usage: resolve-thread <threadId>"
check "resolve-thread with no id: exit code" "$code" 1
check "resolve-thread with an empty id or no id: gh is not called" "$(wc -l < "$GH_STUB_LOG" | tr -d ' ')" "$calls"

# pr-edit. The stand-in gh picks its answer by the pull request's number.
# Pull requests 21 and 27 have a description with a Closes line, 22 has one
# written on GitHub's page (carriage returns), and 23 has none.
calls_of() { grep -c "^$1\$" "$GH_STUB_LOG" || true; } # calls_of <"pr edit"|"pr view"|...>
same() { if cmp -s "$1" "$2"; then echo same; else echo different; fi; }
title='Fix "quoted" `tick` $HOME back\slash and it'"'"'s, release 1.2.3'
printf '%s\n' "$title" > "$texts/title"
printf 'Closes me/shop#12\n\n### Overview\nRuns `repo.sh pr-edit` and costs $5, or "$HOME".\n\n### Verification\n- back\\slash\n\nBoard item: https://github.com/users/me/projects/1\n' > "$texts/body"

run pr-edit 21 "$texts/title" "$texts/body"
check "pr-edit: standard output" "$out" "UPDATED=https://github.com/me/shop/pull/21"
check "pr-edit: standard error is empty, without gh's hint" "$err" ""
check "pr-edit: exit code" "$code" 0
check "pr-edit: the title reaches gh as written" "$(cat "$GH_STUB_SENT/title")" "$title"
check "pr-edit: the description reaches gh as written" "$(same "$texts/body" "$GH_STUB_SENT/body")" same

# The title file may end with a line break, with a carriage return and a
# line break, with spaces, or with nothing: the title is the same.
for ending in '' '\r\n' '  \n\n'; do
  rm -f "$GH_STUB_SENT/title"
  printf "%s$ending" 'One title, release 1.2.3' > "$texts/title-ending"
  run pr-edit 21 "$texts/title-ending" "$texts/body"
  check "pr-edit, title file ending in '$ending': exit code" "$code" 0
  check "pr-edit, title file ending in '$ending': the title" "$(cat "$GH_STUB_SENT/title" 2> /dev/null || true)" "One title, release 1.2.3"
done

# The Closes guard. A new description without the line is refused before
# anything is changed.
refused() { # refused <what> <number> <bodyFile> <the ERROR line wanted>
  edits="$(calls_of "pr edit")"
  run pr-edit "$2" "$texts/title" "$3"
  check "pr-edit, $1: standard output is empty" "$out" ""
  check "pr-edit, $1: standard error" "$err" "$4"
  check "pr-edit, $1: exit code" "$code" 1
  check "pr-edit, $1: gh pr edit is not called" "$(calls_of "pr edit")" "$edits"
}
accepted() { # accepted <what> <number> <bodyFile>
  run pr-edit "$2" "$texts/title" "$3"
  check "pr-edit, $1: standard output" "$out" "UPDATED=https://github.com/me/shop/pull/$2"
  check "pr-edit, $1: standard error" "$err" ""
  check "pr-edit, $1: exit code" "$code" 0
  check "pr-edit, $1: the description reaches gh as written" "$(same "$3" "$GH_STUB_SENT/body")" same
}
dropped='ERROR: the new description drops the line "Closes me/shop#12", which links the pull request to its issue: keep that line. Nothing was changed'
printf '### Overview\nThe line is gone.\n' > "$texts/no-closes"
refused "the Closes line is gone" 21 "$texts/no-closes" "$dropped"
printf 'This Closes me/shop#12 in the middle of a line.\n' > "$texts/closes-inside"
refused "the Closes line is no longer a line of its own" 21 "$texts/closes-inside" "$dropped"
printf 'Closes me/shop#13\n' > "$texts/closes-other"
refused "the Closes line names another issue" 21 "$texts/closes-other" "$dropped"
: > "$texts/empty"
refused "the new description is empty" 21 "$texts/empty" "$dropped"
printf 'Closes me/shop#12\n' > "$texts/one-of-two"
refused "one of two Closes lines is gone" 27 "$texts/one-of-two" \
  'ERROR: the new description drops the line "Closes other/repo#3", which links the pull request to its issue: keep that line. Nothing was changed'

printf 'New words.\n\nCloses me/shop#12\n' > "$texts/moved"
accepted "the Closes line moved down" 21 "$texts/moved"
printf 'Closes me/shop#12  \r\nNew words.\r\n' > "$texts/windows"
accepted "the new description has carriage returns" 21 "$texts/windows"
printf 'Closes me/shop#12' > "$texts/no-line-break"
accepted "the new description ends without a line break" 21 "$texts/no-line-break"
accepted "the current description has carriage returns" 22 "$texts/moved"
accepted "the current description has no Closes line" 23 "$texts/no-closes"
accepted "the current description has no Closes line, and the new one is empty" 23 "$texts/empty"

# pr-edit when gh fails: nothing on standard output, one ERROR line with gh's
# message on standard error, and exit 1.
refused "unknown pull request" 404 "$texts/body" \
  "ERROR: couldn't read pull request 404: GraphQL: Could not resolve to a PullRequest with the number of 404. (repository.pullRequest)"
gave_up() { # gave_up <what> <number> <the ERROR line wanted>
  run pr-edit "$2" "$texts/title" "$texts/body"
  check "pr-edit, $1: standard output is empty" "$out" ""
  check "pr-edit, $1: standard error" "$err" "$3"
  check "pr-edit, $1: exit code" "$code" 1
}
gave_up "GitHub refuses the change" 24 \
  "ERROR: couldn't update pull request 24: GraphQL: me does not have the correct permissions to execute \`UpdatePullRequest\` (updatePullRequest)"
gave_up "gh's message ends with a carriage return" 25 \
  "ERROR: couldn't update pull request 25: GraphQL: Something went wrong while executing your query. (updatePullRequest)"
gave_up "gh prints no link" 26 "ERROR: gh did not confirm the change to pull request 26"

# pr-edit stops before it calls GitHub when its arguments or its title are
# wrong, or when the temporary file can't be made.
unasked() { # unasked <what> <the ERROR line wanted> [first folder in PATH] -- <arguments>
  local what="$1" wanted="$2" before; shift 2
  before="$(wc -l < "$GH_STUB_LOG" | tr -d ' ')"
  run pr-edit ${1+"$@"}
  check "pr-edit, $what: standard output is empty" "$out" ""
  check "pr-edit, $what: standard error" "$err" "$wanted"
  check "pr-edit, $what: exit code" "$code" 1
  check "pr-edit, $what: gh is not called" "$(wc -l < "$GH_STUB_LOG" | tr -d ' ')" "$before"
}
usage="ERROR: usage: pr-edit <number|link> <titleFile> <bodyFile>"
unasked "no arguments" "$usage"
unasked "two arguments" "$usage" 21 "$texts/title"
unasked "four arguments" "$usage" 21 "$texts/title" "$texts/body" more
unasked "an empty first argument" "$usage" "" "$texts/title" "$texts/body"
unasked "no title file" "ERROR: title file not found: $texts/none" 21 "$texts/none" "$texts/body"
unasked "no body file" "ERROR: body file not found: $texts/none" 21 "$texts/title" "$texts/none"
unasked "an empty title file" "ERROR: the title file is empty: $texts/empty" 21 "$texts/empty" "$texts/body"
printf ' \r\n\n' > "$texts/blank"
unasked "a title file with only spaces and line breaks" "ERROR: the title file is empty: $texts/blank" 21 "$texts/blank" "$texts/body"
printf 'One line\nand another\n' > "$texts/two-lines"
unasked "a title of two lines" "ERROR: the title must be one line: $texts/two-lines" 21 "$texts/two-lines" "$texts/body"
first="$nomktemp" unasked "no temporary file" "ERROR: couldn't create a temporary file, so nothing was changed" 21 "$texts/title" "$texts/body"

# The command list of repo.sh names pr-edit.
run help
listed=no
case "$out" in *"pr-edit <number|link> <titleFile> <bodyFile>"*) listed=yes ;; esac
check "repo.sh help lists pr-edit" "$listed" yes

[ "$fail" = 0 ] && echo "PASS: $passed checks"
exit "$fail"
