#!/usr/bin/env bash
# Updates the installed vibe-engineering plugin to the latest published version,
# and reports what changed. Prints KEY=value lines; exits non-zero on a blocking
# problem. Needs the Claude Code CLI (claude). The GitHub CLI (gh) is optional:
# without it, the published state can't be compared (REMOTE_SHA=unknown).
#
# Exit codes:
#   0  ok (updated, or already up to date)
#   2  claude is not installed
#   3  the plugin is not installed
#   4  the update failed
#
# Settings (environment variables):
#   VIBE_ENGINEERING_PLUGIN   default: vibe-engineering@vibe-engineering
#   VIBE_ENGINEERING_REPO     default: gelonezi/vibe-engineering
#   CLAUDE_CONFIG_DIR         default: ~/.claude
set -uo pipefail

PLUGIN="${VIBE_ENGINEERING_PLUGIN:-vibe-engineering@vibe-engineering}"
MARKETPLACE="${PLUGIN#*@}"
REPO="${VIBE_ENGINEERING_REPO:-gelonezi/vibe-engineering}"
RECORD="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/installed_plugins.json"

# First string value of a key in a one-line JSON result.
json_field() { printf '%s' "$2" | sed -nE "s/.*\"$1\":\"([^\"]*)\".*/\1/p" | head -n 1; }

# The commit the installed copy was built from, read from this plugin's block only.
installed_sha() {
  [ -f "$RECORD" ] || return 0
  awk -v p="\"$PLUGIN\"" 'index($0, p) { on = 1 } on && /gitCommitSha/ { print; exit } on && /\]/ { exit }' "$RECORD" \
    | sed -nE 's/.*"gitCommitSha": *"([0-9a-f]+)".*/\1/p'
}

if ! command -v claude >/dev/null 2>&1; then
  echo "STATUS=claude_missing"
  echo "FIX=Install Claude Code, then run this again: https://claude.com/claude-code"
  exit 2
fi

before="$(installed_sha)"
if [ -z "$before" ]; then
  echo "STATUS=not_installed"
  echo "FIX=Run: claude plugin marketplace add $REPO && claude plugin install $PLUGIN"
  exit 3
fi
echo "INSTALLED_SHA_BEFORE=$before"

# 1. Refresh the marketplace, so the update sees the latest published commit.
if ! out="$(claude plugin marketplace update "$MARKETPLACE" 2>&1)"; then
  echo "STATUS=marketplace_update_failed"
  echo "ERROR=$(printf '%s' "$out" | tr '\n' ' ')"
  exit 4
fi

# 2. Update the plugin.
out="$(claude plugin update "$PLUGIN" --json 2>&1)"
rc=$?
line="$(printf '%s\n' "$out" | grep '"command":"update"' | tail -n 1)"
echo "OLD_VERSION=$(json_field oldVersion "$line")"
echo "NEW_VERSION=$(json_field newVersion "$line")"
echo "MESSAGE=$(json_field message "$line")"
if [ $rc -ne 0 ] || [ "$(json_field outcome "$line")" != "ok" ]; then
  echo "STATUS=update_failed"
  echo "ERROR=$(printf '%s' "$out" | tr '\n' ' ')"
  exit 4
fi
update_outcome="$(json_field updateOutcome "$line")"
echo "UPDATE_OUTCOME=$update_outcome"
if [ "$update_outcome" = "up_to_date" ]; then
  echo "RESTART=no"
else
  echo "RESTART=required"
fi

# 3. Compare with what's published.
after="$(installed_sha)"
echo "INSTALLED_SHA=$after"
remote="$(gh api "repos/$REPO/commits/main" --jq .sha 2>/dev/null || true)"
echo "REMOTE_SHA=${remote:-unknown}"
if [ -n "$remote" ] && [ "$after" != "$remote" ]; then
  echo "BEHIND=true"
  echo "FIX=The published plugin has commits that the installed version number doesn't cover. Force them in with: claude plugin uninstall $PLUGIN && claude plugin install $PLUGIN"
else
  echo "BEHIND=false"
fi

# 4. What changed since the copy that was installed before this run.
if [ -n "$remote" ] && [ "$before" != "$remote" ]; then
  gh api "repos/$REPO/compare/$before...$remote" \
    --jq '.commits[] | "CHANGE=" + (.commit.message | split("\n")[0])' 2>/dev/null || true
fi

echo "STATUS=ok"
