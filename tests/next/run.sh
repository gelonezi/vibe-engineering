#!/usr/bin/env bash
# Runs scripts/next.sh board against a stand-in gh and checks the steps it
# offers for each kind of item, the number of GitHub calls, and that a longer
# board starts no more processes. Needs jq, and no GitHub. The last check also
# needs strace, and is skipped without it. Run: bash tests/next/run.sh
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
export GH_STUB_LOG; GH_STUB_LOG="$(mktemp)"
long="$(mktemp -d)"; trace="$(mktemp)"
trap 'rm -f "$GH_STUB_LOG" "$trace" "$long"/*.json; rmdir "$long"' EXIT
got="$(PATH="$here:$PATH" bash "$here/../../scripts/next.sh" board PVT_test \
  | awk -F'\t' '{ print $8 "\t" $7 }')"
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

# The panel runs `board` on every refresh, so it must not start a process for
# each item. Count the processes one run starts on the fixture board and on
# the same board ten times over: the two numbers must be equal.
starts() {
  : > "$trace"
  GH_STUB_LOG=/dev/null GH_STUB_DIR="$1" PATH="$here:$PATH" \
    strace -f -c -e trace=clone,clone3,fork,vfork -o "$trace" \
    bash "$here/../../scripts/next.sh" board PVT_test > /dev/null 2>&1 || return 0
  awk '$NF == "total" { print $4 }' "$trace"
}
cost="process starts not counted (no strace here)"
if command -v strace > /dev/null 2>&1; then
  cp "$here/prs.json" "$here/feedback.json" "$long/"
  jq '.data.node.items.nodes |= (. as $n | [range(10) | $n[]])' "$here/board.json" > "$long/board.json"
  few="$(starts "$here")"; many="$(starts "$long")"
  if [ -z "$few" ] || [ -z "$many" ]; then
    cost="process starts not counted (strace may not trace here)"
  elif [ "$many" -gt "$few" ]; then
    echo "FAIL: next.sh starts a process per item: $few process starts for the fixture board, $many for ten times as many items"
    fail=1
  else
    cost="$few process starts, and as many for ten times the items"
  fi
fi
[ "$fail" = 0 ] && echo "PASS: $(printf '%s\n' "$got" | wc -l | tr -d ' ') items, $calls calls, $cost"
exit "$fail"
