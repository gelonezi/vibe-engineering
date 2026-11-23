#!/usr/bin/env bash
# Pull requests and issues, used by the develop, push, review and approve skills.
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
#   pr-comments <number|link>           What reviewers wrote, one row per comment:
#                                       "<kind>\t<author>\t<state>\t<path>\t<line>\t<body>", then COMMENTS=<n>.
#                                       kind is review, inline or general. state is the verdict for a
#                                       review, open or resolved for an inline comment, and - otherwise.
#                                       A line break in a body is written as \n. Read-only.
#   checks <number|link>                One line per check, then CHECKS=pass|fail|pending|none
#   pr-review <prLink> <payloadFile>    Post one review with inline comments, prints its URL.
#                                       The payload is GitHub's JSON: {"event":"COMMENT","body":"...",
#                                       "comments":[{"path":"a.ts","line":12,"side":"RIGHT","body":"..."}]}
#   merge-settings                      "<defaultBranch>\t<squashAllowed>\t<mergeAllowed>\t<rebaseAllowed>"
#   merge <number|link> <squash|merge|rebase>
#                                       Merge and delete the branch. Can't be undone.
#                                       A squash commit gets the subject "<PR title> (#<number>)".
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

  pr-comments)
    [ $# -eq 1 ] || die "usage: pr-comments <number|link>"
    # The comments query needs the owner, the repository and the number, so
    # resolve the pull request first. An unknown one stops here, with gh's message.
    pr_line="$(gh pr view "$1" --json number,url --jq '[.number, .url] | @tsv')"
    IFS=$'\t' read -r pr_number pr_url <<<"$pr_line"
    pr_path="${pr_url#*://}"; pr_path="${pr_path#*/}"
    pr_owner="${pr_path%%/*}"; pr_path="${pr_path#*/}"; pr_name="${pr_path%%/*}"
    # One call for reviews, inline threads and general comments. The rows are
    # built inside --jq, so there is no pipe. @tsv keeps each body on one line.
    # A review that only carries inline comments has no text of its own and the
    # verdict COMMENTED: it is left out, since its comments are printed anyway.
    gh api graphql -f o="$pr_owner" -f n="$pr_name" -F i="$pr_number" -f query='
      query($o: String!, $n: String!, $i: Int!) {
        repository(owner: $o, name: $n) {
          pullRequest(number: $i) {
            reviews(first: 100) { pageInfo { hasNextPage } nodes { author { login } state body } }
            reviewThreads(first: 100) {
              pageInfo { hasNextPage }
              nodes {
                isResolved path line originalLine
                comments(first: 100) { pageInfo { hasNextPage } nodes { author { login } body } }
              }
            }
            comments(first: 100) { pageInfo { hasNextPage } nodes { author { login } body } }
          }
        }
      }' \
      --jq '.data.repository.pullRequest as $p
        | ([$p.reviews.nodes[]
             | select((.body // "") != "" or .state != "COMMENTED")
             | ["review", (.author.login // "ghost"), .state, "-", "-", (if (.body // "") == "" then "-" else .body end)]]
           + [$p.reviewThreads.nodes[] | . as $t | $t.comments.nodes[]
             | ["inline", (.author.login // "ghost"), (if $t.isResolved then "resolved" else "open" end),
                ($t.path // "-"), (($t.line // $t.originalLine // "-") | tostring),
                (if (.body // "") == "" then "-" else .body end)]]
           + [$p.comments.nodes[]
             | ["general", (.author.login // "ghost"), "-", "-", "-", (if (.body // "") == "" then "-" else .body end)]]
          ) as $rows
        | ($rows[] | @tsv),
          (if ($p.reviews.pageInfo.hasNextPage or $p.reviewThreads.pageInfo.hasNextPage or $p.comments.pageInfo.hasNextPage
               or ([$p.reviewThreads.nodes[].comments.pageInfo.hasNextPage] | any))
           then "WARN=more comments exist than the 100 shown per kind" else empty end),
          "COMMENTS=\($rows | length)"'
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
      # A here-string, not a pipe: no command is left writing when grep stops.
      *) if grep -qi "no checks" <<<"$out"; then echo "CHECKS=none"; else echo "CHECKS=fail"; fi ;;
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
    if [ "$2" = squash ]; then
      # Without a subject, GitHub picks one from the repository's settings, and
      # can take the title of the branch's first commit instead of the pull
      # request's current title. So build it here, as GitHub would: the title,
      # then the number. It is built inside --jq as one string: @tsv would
      # double a backslash in the title. No body is given, so GitHub writes it.
      subject="$(gh pr view "$1" --json number,title --jq '.title + " (#" + (.number | tostring) + ")"')"
      [ -n "$subject" ] || die "couldn't read the title of pull request: $1"
      gh pr merge "$1" --squash --subject "$subject" --delete-branch
    else
      gh pr merge "$1" "--$2" --delete-branch
    fi
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
