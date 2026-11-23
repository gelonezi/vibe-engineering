#!/usr/bin/env bash
# Checks that every script parses: bash -n on each one, with the Bash that
# runs this file. One call per script, because `bash -n a.sh b.sh` checks
# only a.sh and takes b.sh as its argument. Needs only Bash.
# Run: bash tests/syntax.sh            every script of the repository
#      bash tests/syntax.sh <file>...  only these files
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
# A pattern that matches nothing stays as it is written, and is then reported
# as "not a file". So a renamed folder can't leave this check with nothing to
# check.
[ $# -gt 0 ] || set -- "$root"/scripts/*.sh "$root"/skills/*/scripts/*.sh \
  "$root"/tests/*.sh "$root"/tests/*/run.sh "$root"/tests/*/gh
fail=0
for file in "$@"; do
  if [ ! -f "$file" ]; then
    echo "FAIL: $file is not a file"
    fail=1
  elif ! "$BASH" -n "$file"; then
    echo "FAIL: $file does not parse"
    fail=1
  fi
done
[ "$fail" = 0 ] && echo "PASS: $# scripts parse with Bash $BASH_VERSION"
exit "$fail"
