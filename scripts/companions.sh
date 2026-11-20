#!/usr/bin/env bash
# Reports whether the companion plugins that the skills hand work to are
# installed and enabled. Prints KEY=value lines. A missing companion never
# blocks a skill: each skill does that part of the work itself instead.
#
# Output:
#   STATUS=ok | missing | unknown
#   COMPANION=<name> installed | disabled | missing     one line per companion
#   FIX=<command>                                        one line per companion to fix
#
# Exit codes:
#   0  every companion is installed and enabled
#   1  at least one is missing or disabled
#   2  can't tell: the Claude Code CLI (claude) isn't available here
#
# Settings (environment variables):
#   VIBE_ENGINEERING_COMPANIONS             default: the three names below
#   VIBE_ENGINEERING_COMPANION_MARKETPLACE  default: claude-plugins-official
set -uo pipefail

COMPANIONS="${VIBE_ENGINEERING_COMPANIONS:-superpowers code-review claude-md-management}"
MARKETPLACE="${VIBE_ENGINEERING_COMPANION_MARKETPLACE:-claude-plugins-official}"

if ! command -v claude >/dev/null 2>&1 || ! list="$(claude plugin list --json 2>/dev/null)"; then
  echo "STATUS=unknown"
  echo "MESSAGE=The Claude Code CLI isn't available here, so the companion plugins couldn't be checked."
  exit 2
fi

# One line per plugin object, so each line holds one "id" and its "enabled".
flat="$(printf '%s' "$list" | tr -d '\n' | awk '{ gsub(/"id":/, "\n\"id\":"); print }')"

status="ok"
for name in $COMPANIONS; do
  # Any marketplace counts, and so does a copy synced from claude.ai.
  line="$(printf '%s\n' "$flat" | grep -E "^\"id\": *\"$name@" | head -n 1)"
  if [ -z "$line" ]; then
    echo "COMPANION=$name missing"
    echo "FIX=claude plugin install $name@$MARKETPLACE"
    status="missing"
  elif printf '%s' "$line" | grep -Eq '"enabled": *false'; then
    echo "COMPANION=$name disabled"
    id="$(printf '%s' "$line" | sed -E 's/^"id": *"([^"]*)".*/\1/')"
    echo "FIX=claude plugin enable $id"
    status="missing"
  else
    echo "COMPANION=$name installed"
  fi
done

echo "STATUS=$status"
[ "$status" = "ok" ]
