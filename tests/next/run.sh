#!/usr/bin/env bash
# Runs scripts/next.sh board against a stand-in gh and checks the steps it
# offers for each kind of item, the number of GitHub calls, and that a longer
# board starts no more processes. Needs jq (1.7 or newer on Windows), and no
# GitHub. The last check also needs a strace that can trace, which Linux
# has. Elsewhere it is skipped, and the PASS line says so. With
# NEED_STRACE=1, a run that could not count process starts fails instead.
# Run: bash tests/next/run.sh
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
export GH_STUB_LOG; GH_STUB_LOG="$(mktemp)"
long="$(mktemp -d)"; trace="$(mktemp)"
trap 'rm -f "$GH_STUB_LOG" "$trace" "$long"/*.json; rmdir "$long"' EXIT
# Prints "<title>\t<steps>" for each item of the board whose JSON files are in $1.
board() {
  GH_STUB_DIR="$1" PATH="$here:$PATH" bash "$here/../../scripts/next.sh" board PVT_test \
    | awk -F'\t' '{ print $8 "\t" $7 }'
}
got="$(board "$here")"
calls="$(wc -l < "$GH_STUB_LOG" | tr -d ' ')"
fail=0
if [ "$got" != "$(cat "$here/expected.tsv")" ]; then
  echo "FAIL: the steps differ from expected.tsv:"
  diff <(printf '%s\n' "$got") "$here/expected.tsv" || true
  fail=1
fi
if [ "$calls" != 3 ]; then
  echo "FAIL: next.sh made $calls GitHub calls, expected 3"
  fail=1
fi

# The long board is the fixture board ten times over. Each copy gets
# repositories of its own, so the long board has ten times the items, ten
# times the repositories and ten times the pull requests in review. next.sh
# skips a repository or a pull request it has already seen, so plain copies
# would run the code after those skips no more often than the fixture board.
copy='def copy($i): (.. | .nameWithOwner? | strings) |= "\(.)-\($i)";'
jq "$copy"' .data.node.items.nodes |= (. as $n | [range(10) as $i | $n[] | copy($i)])' \
  "$here/board.json" > "$long/board.json"
for file in prs feedback; do
  jq "$copy"' .data |= (. as $d | [range(10) as $i | $d | to_entries[]
    | { key: "\(.key)c\($i)", value: (.value | copy($i)) }] | from_entries)' \
    "$here/$file.json" > "$long/$file.json"
done
# Every copy must get the steps of expected.tsv. If one did not, the long
# board would not be the fixture board ten times, and the count below would
# prove nothing.
if [ "$(GH_STUB_LOG=/dev/null board "$long")" != "$(for i in 0 1 2 3 4 5 6 7 8 9; do cat "$here/expected.tsv"; done)" ]; then
  echo "FAIL: ten copies of the fixture board do not get the steps of expected.tsv ten times"
  fail=1
fi

# The panel runs `board` on every refresh, so it must not start a process for
# each item, each repository or each pull request. Count the processes one run
# starts on the fixture board and on the long board: the two numbers must be
# equal.
starts() {
  : > "$trace"
  GH_STUB_LOG=/dev/null GH_STUB_DIR="$1" PATH="$here:$PATH" \
    strace -f -c -e trace=clone,clone3,fork,vfork -o "$trace" \
    bash "$here/../../scripts/next.sh" board PVT_test > /dev/null 2>&1 || return 0
  awk '$NF == "total" { print $4 }' "$trace"
}
cost="process starts not counted (no strace here)"
if command -v strace > /dev/null 2>&1; then
  few="$(starts "$here")"; many="$(starts "$long")"
  if [ -z "$few" ] || [ -z "$many" ]; then
    cost="process starts not counted (strace may not trace here)"
  elif [ "$many" -gt "$few" ]; then
    echo "FAIL: next.sh starts a process per item, repository or pull request: $few process starts for the fixture board, $many for ten times as many"
    fail=1
    # The count was made, so the NEED_STRACE check below has nothing to say.
    cost="$few process starts, and $many for ten times as many"
  else
    cost="$few process starts, and as many for ten times the items, repositories and pull requests"
  fi
fi
case "$cost" in
  "process starts not counted"*)
    if [ "${NEED_STRACE:-}" = 1 ]; then
      echo "FAIL: NEED_STRACE=1, but $cost"
      fail=1
    fi ;;
esac
[ "$fail" = 0 ] && echo "PASS: $(printf '%s\n' "$got" | wc -l | tr -d ' ') items, $calls calls, $cost"
exit "$fail"
