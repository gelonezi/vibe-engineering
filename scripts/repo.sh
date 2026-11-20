#!/usr/bin/env bash
# Pull requests and issues, used by the push, review and approve skills.
# Runs in the current git repository unless a link names another one.
# Needs only gh; no jq.
#
# Usage: repo.sh <command> [args]
#
#   pr <number|link|branch>             "<number>\t<state>\t<isDraft>\t<mergeable>\t<mergeStateStatus>\t<reviewDecision>\t<headBranch>\t<baseBranch>\t<url>\t<title>"
#   pr-for-branch <branch>              The open PR for a branch: "<number>\t<url>", or nothing
#   pr-create <title> <bodyFile>        Open a PR from the current branch, prints its URL
#   pr-body <number|link>               The PR's description
#   pr-diff <number|link>               The PR's diff
#   checks <number|link>                One line per check, then CHECKS=pass|fail|pending|none
#   pr-review <prLink> <payloadFile>    Post one review with inline comments, prints its URL.
#                                       The payload is GitHub's JSON: {"event":"COMMENT","body":"...",
#                                       "comments":[{"path":"a.ts","line":12,"side":"RIGHT","body":"..."}]}
#   merge-settings                      "<defaultBranch>\t<squashAllowed>\t<mergeAllowed>\t<rebaseAllowed>"
#   merge <number|link> <squash|merge|rebase>
#                                       Merge and delete the branch. Can't be undone.
#   issue-parent <owner/name> <number>  The issue's parent, if any:
#                                       "<parentNumber>\t<parentState>\t<completedSubIssues>\t<totalSubIssues>"
#   issue-close <owner/name> <number>   Close an issue
set -euo pipefail

die() { echo "ERROR: $*" >&2; exit 1; }

cmd="${1:-}"; shift || true

case "$cmd" in
  pr)
    [ $# -eq 1 ] || die "usage: pr <number|link|branch>"
    gh pr view "$1" --json number,state,isDraft,mergeable,mergeStateStatus,reviewDecision,headRefName,baseRefName,url,title \
      --jq '[.number, .state, .isDraft, .mergeable, .mergeStateStatus, (if (.reviewDecision // "") == "" then "NONE" else .reviewDecision end), .headRefName, .baseRefName, .url, .title] | @tsv'
    ;;

  pr-for-branch)
    [ $# -eq 1 ] || die "usage: pr-for-branch <branch>"
    gh pr list --head "$1" --state open --json number,url --jq '.[0] // empty | [.number, .url] | @tsv'
    ;;

  pr-create)
    [ $# -eq 2 ] || die "usage: pr-create <title> <bodyFile>"
    [ -f "$2" ] || die "body file not found: $2"
    gh pr create --title "$1" --body-file "$2"
    ;;

  pr-body)
    [ $# -eq 1 ] || die "usage: pr-body <number|link>"
    gh pr view "$1" --json body --jq '.body'
    ;;

  pr-diff)
    [ $# -eq 1 ] || die "usage: pr-diff <number|link>"
    gh pr diff "$1"
    ;;

  checks)
    [ $# -eq 1 ] || die "usage: checks <number|link>"
    # gh exits 8 while checks are pending and 1 when one failed or none exist.
    set +e
    out="$(gh pr checks "$1" 2>&1)"; code=$?
    set -e
    printf '%s\n' "$out"
    case "$code" in
      0) echo "CHECKS=pass" ;;
      8) echo "CHECKS=pending" ;;
      *) if printf '%s' "$out" | grep -qi "no checks"; then echo "CHECKS=none"; else echo "CHECKS=fail"; fi ;;
    esac
    ;;

  pr-review)
    [ $# -eq 2 ] || die "usage: pr-review <prLink> <payloadFile>"
    [ -f "$2" ] || die "payload file not found: $2"
    slug="$(printf '%s' "$1" | sed -E 's#^[a-z]+://[^/]+/##')"
    case "$slug" in
      */*/pull/[0-9]*) ;;
      *) die "expected a pull request link, got: $1" ;;
    esac
    owner="${slug%%/*}"; rest="${slug#*/}"; name="${rest%%/*}"
    number="$(printf '%s' "$slug" | sed -E 's#^[^/]+/[^/]+/pull/([0-9]+).*#\1#')"
    gh api --method POST "repos/$owner/$name/pulls/$number/reviews" --input "$2" --jq '.html_url'
    ;;

  merge-settings)
    [ $# -eq 0 ] || die "usage: merge-settings"
    gh repo view --json defaultBranchRef,squashMergeAllowed,mergeCommitAllowed,rebaseMergeAllowed \
      --jq '[.defaultBranchRef.name, .squashMergeAllowed, .mergeCommitAllowed, .rebaseMergeAllowed] | @tsv'
    ;;

  merge)
    [ $# -eq 2 ] || die "usage: merge <number|link> <squash|merge|rebase>"
    case "$2" in squash|merge|rebase) ;; *) die "unknown merge method: $2" ;; esac
    gh pr merge "$1" "--$2" --delete-branch
    ;;

  issue-parent)
    [ $# -eq 2 ] || die "usage: issue-parent <owner/name> <number>"
    gh api graphql -f o="${1%%/*}" -f n="${1#*/}" -F i="$2" -f query='
      query($o: String!, $n: String!, $i: Int!) {
        repository(owner: $o, name: $n) {
          issue(number: $i) { parent { number state subIssuesSummary { total completed } } }
        }
      }' \
      --jq '.data.repository.issue.parent // empty | [.number, .state, .subIssuesSummary.completed, .subIssuesSummary.total] | @tsv'
    ;;

  issue-close)
    [ $# -eq 2 ] || die "usage: issue-close <owner/name> <number>"
    gh issue close "$2" --repo "$1"
    ;;

  ""|-h|--help|help)
    awk 'NR == 1 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "$0"
    ;;

  *)
    die "unknown command: $cmd (try: $0 help)"
    ;;
esac
