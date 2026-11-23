#!/usr/bin/env bash
# Runs scripts/next.sh board against a stand-in gh and checks the steps it
# offers for each kind of item. Needs jq, and no GitHub. Run: bash tests/next/run.sh
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
export GH_STUB_LOG; GH_STUB_LOG="$(mktemp)"
trap 'rm -f "$GH_STUB_LOG"' EXIT
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
[ "$fail" = 0 ] && echo "PASS: $(printf '%s\n' "$got" | wc -l | tr -d ' ') items, $calls calls"
exit "$fail"
