#!/usr/bin/env bash
# Checks that the GitHub CLI is installed, logged in, and allowed to use
# GitHub Projects. Prints KEY=value lines; exits non-zero on a blocking problem.
#
# Exit codes:
#   0  ready
#   2  gh is not installed
#   3  gh is not logged in
#   4  token is missing the "project" scope (classic token / OAuth login)
#   5  the Projects API rejected the token (fine-grained token without access, SSO, ...)
#   6  this environment blocks GitHub's Projects API, whatever the token
#      (Claude Code cloud sessions); STATUS=projects_unavailable
#   7  the GitHub CLI is too old to have the "gh project" commands
set -uo pipefail

host="${GH_HOST:-github.com}"

if ! command -v gh >/dev/null 2>&1; then
  echo "STATUS=gh_missing"
  echo "FIX=Install the GitHub CLI: https://cli.github.com/ then run: gh auth login -s project"
  exit 2
fi

if ! login="$(gh api user --hostname "$host" --jq .login 2>/dev/null)" || [ -z "$login" ]; then
  echo "STATUS=not_logged_in"
  echo "FIX=Run: gh auth login --hostname $host -s project"
  exit 3
fi
echo "LOGIN=$login"
echo "HOST=$host"

# Live check, done first: can this session reach Projects at all? Some
# environments refuse every GraphQL call, and no token change fixes that.
probe_ok=true
if ! probe_err="$(gh api graphql --hostname "$host" \
      -f query='query { viewer { projectsV2(first: 1) { totalCount } } }' 2>&1 >/dev/null)"; then
  probe_ok=false
  probe_err="$(printf '%s' "$probe_err" | tr '\n' ' ')"
  case "$probe_err" in
    *"GraphQL is not available"*)
      echo "STATUS=projects_unavailable"
      echo "ERROR=$probe_err"
      echo "FIX=This session can't reach GitHub Projects, and a new token won't change that. Use Claude Code on your own computer."
      exit 6
      ;;
  esac
fi

if ! gh project --help >/dev/null 2>&1; then
  echo "STATUS=gh_outdated"
  echo "FIX=Update the GitHub CLI (https://cli.github.com/): this version has no 'gh project' commands."
  exit 7
fi

# A token from GH_TOKEN / GITHUB_TOKEN wins over the stored login, and
# `gh auth refresh` cannot change its scopes.
token_source="gh_login"
if [ -n "${GH_TOKEN:-}" ] || [ -n "${GITHUB_TOKEN:-}" ]; then
  token_source="env_var"
fi
echo "TOKEN_SOURCE=$token_source"

# Classic tokens and OAuth logins report their scopes in X-OAuth-Scopes.
# Fine-grained tokens and GitHub App tokens send no such header.
scopes="$(gh api -i user --hostname "$host" 2>/dev/null \
  | tr -d '\r' \
  | awk -F': ' 'tolower($1)=="x-oauth-scopes" {print $2; exit}')"

if [ -n "$scopes" ]; then
  echo "TOKEN_KIND=classic_or_oauth"
  echo "SCOPES=$scopes"
  has_scope() { printf '%s' "$scopes" | tr -d ' ' | tr ',' '\n' | grep -qx "$1"; }
  if ! has_scope project; then
    echo "STATUS=missing_project_scope"
    if [ "$token_source" = "env_var" ]; then
      echo "FIX=The token in GH_TOKEN/GITHUB_TOKEN lacks the 'project' scope. Create a token with 'project' (and 'repo' to link private repos), or unset the variable and run: gh auth login -s project"
    else
      echo "FIX=Run: gh auth refresh --hostname $host -s project"
    fi
    exit 4
  fi
  if ! has_scope repo && ! has_scope public_repo; then
    echo "WARN=No 'repo' scope: linking the board to a repository may fail. Fix with: gh auth refresh -s repo"
  fi
  if ! has_scope read:org && ! has_scope admin:org; then
    echo "WARN=No 'read:org' scope: your organizations may not be listed. Fix with: gh auth refresh -s read:org"
  fi
else
  echo "TOKEN_KIND=fine_grained_or_app"
  echo "WARN=Token scopes cannot be read for this token type. It needs 'Projects: Read and write' (account or organization permission)."
fi

if [ "$probe_ok" != true ]; then
  echo "STATUS=projects_api_denied"
  echo "ERROR=$probe_err"
  echo "FIX=Give the token Projects read/write access (classic: 'project' scope; fine-grained: Projects permission), and authorize SSO for the organization if it uses SAML."
  exit 5
fi

echo "STATUS=ok"
