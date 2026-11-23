#!/usr/bin/env bash
# Runs the review thread commands of scripts/repo.sh (pr-threads, pr-comments
# and resolve-thread) against a stand-in gh, and checks what they print on
# standard output and on standard error, and how they exit. It also checks
# that repo.sh and next.sh read the same end of a pull request's list of
# review threads. Needs jq, and no GitHub. Run: bash tests/repo/run.sh
set -euo pipefail
command -v jq > /dev/null 2>&1 || { echo "FAIL: this test needs jq, and jq is not installed"; exit 1; }
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../.." && pwd)"
export GH_STUB_LOG; GH_STUB_LOG="$(mktemp)"
errf="$(mktemp)"
nomktemp="$(mktemp -d)"
trap 'rm -rf "$GH_STUB_LOG" "$errf" "$nomktemp"' EXIT
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

[ "$fail" = 0 ] && echo "PASS: $passed checks"
exit "$fail"
