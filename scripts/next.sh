#!/usr/bin/env bash
# What comes next for each item on a vibe-engineering board: the one place
# that maps a column to the skill that moves an item out of it. The ui skill
# and the side panel both read it, so they can never disagree. Needs only gh;
# no jq.
#
# Usage: next.sh <command> [args]
#
#   board <projectId>                   One line per item, in board order:
#                                       "<itemId>\t<status>\t<type>\t<number>\t<repo>\t<subDone>/<subTotal>\t<steps>\t<title>"
#   steps <status> [type] [subTotal] [pr]
#                                       The steps alone, for one item: "<steps>"
#
# <steps> is a comma-separated list of "<skill>:<label>", in the order to offer
# them, or "-" when nothing is started from here: a Done item, an item with no
# status, a pull request added to the board, or a parent whose sub-issues carry
# the work. <type> is DRAFT_ISSUE, ISSUE or PULL_REQUEST, and <number> and
# <repo> are "-" for a draft issue. Labels never hold a comma or a colon.
#
# <pr> is what the item's open pull request says: "comments" when there is
# review feedback to act on, "open" when there is none, or "-" when no open
# pull request was found. `board` finds it as the other skills do, by its
# branch `feature/<number>-<slug>`, and else by the "Closes <repo>#<number>"
# line push writes. There is feedback to act on when:
#   - a reviewer's latest verdict requests changes. It stays until they review
#     again, whatever is committed. It is read from GitHub's own list of each
#     reviewer's latest verdict, which holds the reviewers who can push, and
#     from the last 50 reviews for everyone else,
#   - a review thread is unresolved (push offers to resolve the ones develop
#     fixed, once the fix is on the PR). The threads read are the newest 100,
#     the same ones repo.sh pr-threads lists,
#   - a review with only text, and no comments on lines, was written after the
#     PR's latest commit by anyone but a bot. The PR's author counts here: when
#     GitHub rejects the lines, the review skill puts every comment in the
#     review's text, and in a solo project the reviewer is the author, or
#   - someone other than the PR's author, and not a bot, wrote other text
#     after the PR's latest commit: a review that also has comments on lines,
#     or a plain comment.
# Text can't be resolved, so a later commit is taken as the answer to it. The
# author's plain comments and replies in threads never count.
# One case is accepted as it is: when the author deletes every comment on a
# line from their own review, GitHub reports it as a review with only text, and
# no field tells the two apart. Its text then counts until the next commit.
# "Fix comments" is offered for "comments", and for "-", when there is no way
# to tell. In progress says "Update the pull request" once one is open. `board`
# makes at most three calls: the board, the open PRs of every repository with
# work in progress or in review, and the feedback of every PR in review. It
# starts no process per item, so a refresh costs the same on a long board.
set -euo pipefail

die() { echo "ERROR: $*" >&2; exit 1; }

# Sets `steps` to the steps for one item, from its status in lower case. Keep
# in step with docs/concept.md. It sets a variable, and `stage_of` and `pr_for`
# do too, because `board` calls them for every item: printing the answer for
# the caller to capture would start a process each time.
steps_for() {
  local type total pr
  type="${2:-ISSUE}"
  total="${3:-0}"
  pr="${4:--}"
  case "$total" in ''|*[!0-9]*) total=0 ;; esac

  steps="-"
  if [ "$type" = "PULL_REQUEST" ] || [ "$total" -gt 0 ]; then
    return
  fi
  case "${1:-}" in
    draft)         steps="promote-backlog:Design it" ;;
    backlog)       steps="promote-ready:Write the spec" ;;
    ready)         steps="develop:Build it" ;;
    "in progress")
      if [ "$pr" = "-" ]; then steps="push:Open the pull request"
      else steps="push:Update the pull request"; fi ;;
    "in review")
      if [ "$pr" = "open" ]; then steps="review:Review,approve:Merge"
      else steps="review:Review,develop:Fix comments,approve:Merge"; fi ;;
  esac
}

cmd="${1:-}"; shift || true

case "$cmd" in
  steps)
    [ $# -ge 1 ] && [ $# -le 4 ] || die "usage: steps <status> [type] [subTotal] [pr]"
    low="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"; shift
    steps_for "$low" "$@"
    echo "$steps"
    ;;

  board)
    [ $# -eq 1 ] || die "usage: board <projectId>"
    # --paginate follows $endCursor, so boards with more than 100 items are read in full.
    # The status comes back a second time in lower case, so that no process is
    # started here to lower-case it.
    rows="$(gh api graphql --paginate -f p="$1" -f query='
      query($p: ID!, $endCursor: String) {
        node(id: $p) {
          ... on ProjectV2 {
            items(first: 100, after: $endCursor) {
              pageInfo { hasNextPage endCursor }
              nodes {
                id
                type
                fieldValueByName(name: "Status") { ... on ProjectV2ItemFieldSingleSelectValue { name } }
                content {
                  __typename
                  ... on DraftIssue { title }
                  ... on Issue {
                    number title repository { nameWithOwner } subIssuesSummary { total completed }
                    closedByPullRequestsReferences(first: 5, includeClosedPrs: false) {
                      nodes { number state repository { nameWithOwner } }
                    }
                  }
                  ... on PullRequest { number title repository { nameWithOwner } }
                }
              }
            }
          }
        }
      }' \
      --jq '.data.node.items.nodes[]? | [
        .id,
        (.fieldValueByName.name // "~"),
        ((.fieldValueByName.name // "~") | ascii_downcase),
        (.type // "~"),
        (.content.number // "-"),
        (.content.repository.nameWithOwner // "-"),
        "\(.content.subIssuesSummary.completed // 0)/\(.content.subIssuesSummary.total // 0)",
        ([.content.closedByPullRequestsReferences.nodes[]? | select(.state == "OPEN")
          | "\(.repository.nameWithOwner)#\(.number)"] | first // "-"),
        (.content.title // "")
      ] | @tsv')"
    [ -n "$rows" ] || exit 0

    # Which items have a pull request to look at: an issue of its own (not a
    # parent), in progress or in review. Sets `stage` to "in progress" or
    # "in review", or to nothing. Takes the status in lower case.
    stage_of() {
      stage=""
      [ "$2" = "ISSUE" ] && [ "$3" != "-" ] && [ "${4#*/}" = "0" ] || return 0
      case "$1" in "in progress"|"in review") stage="$1" ;; esac
    }
    # A repository name goes into a query as text, so take only safe ones.
    safe_repo() { case "$1" in */*) ;; *) return 1 ;; esac; case "$1" in *[!A-Za-z0-9._/-]*) return 1 ;; esac; }

    # Call 2: the open pull requests of each repository, as
    # "<repo>\t<headBranch>\t<number>" lines.
    repos=" "; query=""; k=0
    while IFS=$'\t' read -r id status low type number repo subs linked title; do
      stage_of "$low" "$type" "$number" "$subs"
      [ -n "$stage" ] || continue
      safe_repo "$repo" || continue
      case "$repos" in *" $repo "*) continue ;; esac
      repos="$repos$repo "
      query="$query r$k: repository(owner: \"${repo%%/*}\", name: \"${repo#*/}\") {
        nameWithOwner
        pullRequests(states: OPEN, first: 100, orderBy: { field: UPDATED_AT, direction: DESC }) { nodes { number headRefName } }
      }"
      k=$((k + 1))
    done <<< "$rows"
    open_prs=""
    if [ -n "$query" ]; then
      open_prs="$(gh api graphql -f query="query { $query }" \
        --jq '.data[]? | select(. != null) | .nameWithOwner as $r
          | .pullRequests.nodes[] | "\($r)\t\(.headRefName)\t\(.number)"' \
        </dev/null 2>/dev/null || true)"
    fi

    # Sets `found` to the issue's pull request, as "<repo>#<number>", or "-".
    pr_for() {
      local r head n
      found="$3"
      while IFS=$'\t' read -r r head n; do
        [ "$r" = "$1" ] || continue
        case "$head" in "feature/$2-"*) found="$r#$n"; return ;; esac
      done <<< "$open_prs"
    }

    # Call 3: the feedback state of each pull request in review, as
    # "<repo>#<number>\t<comments|open>" lines.
    query=""; k=0; wanted=" "
    while IFS=$'\t' read -r id status low type number repo subs linked title; do
      stage_of "$low" "$type" "$number" "$subs"
      [ "$stage" = "in review" ] || continue
      pr_for "$repo" "$number" "$linked"
      [ "$found" != "-" ] && safe_repo "${found%#*}" || continue
      case "$wanted" in *" $found "*) continue ;; esac
      wanted="$wanted$found "
      name="${found%#*}"; name="${name#*/}"
      query="$query p$k: repository(owner: \"${found%%/*}\", name: \"$name\") {
        pullRequest(number: ${found##*#}) { ...F }
      }"
      k=$((k + 1))
    done <<< "$rows"
    # A reviewer's latest verdict is read twice. latestOpinionatedReviews is
    # exact however many reviews came later, but lists only reviewers who can
    # push. The last 50 reviews cover the others. A review with text counts
    # from the PR's author only when it has no comments on lines: then nothing
    # else carries its feedback. A reply in a thread is a review with no text.
    feedback=""
    if [ -n "$query" ]; then
      feedback="$(gh api graphql -f query="query { $query }
        fragment F on PullRequest {
          number repository { nameWithOwner } author { login } reviewDecision
          commits(last: 1) { nodes { commit { committedDate } } }
          latestOpinionatedReviews(first: 100) { nodes { state } }
          reviews(last: 50) { nodes { state body submittedAt comments { totalCount } author { __typename login } } }
          reviewThreads(last: 100) { nodes { isResolved } }
          comments(last: 50) { nodes { publishedAt author { __typename login } } }
        }" \
        --jq '.data[]? | .pullRequest? | select(. != null) | . as $p
          | ($p.author.login // "") as $me
          | ($p.commits.nodes[0].commit.committedDate // "") as $since
          | ( $p.reviewDecision == "CHANGES_REQUESTED"
              or any($p.latestOpinionatedReviews.nodes[]?; .state == "CHANGES_REQUESTED")
              or ([$p.reviews.nodes[] | select(.state == "APPROVED" or .state == "CHANGES_REQUESTED" or .state == "DISMISSED")]
                  | group_by(.author.login // "") | map(max_by(.submittedAt).state) | any(.[]; . == "CHANGES_REQUESTED"))
              or any($p.reviewThreads.nodes[]; .isResolved | not)
              or any((($p.reviews.nodes[] | select(.state == "COMMENTED" and (.body // "") != "")
                        | {a: .author, t: .submittedAt, alone: ((.comments.totalCount // 0) == 0)}),
                      ($p.comments.nodes[] | {a: .author, t: .publishedAt, alone: false}));
                     (.a.__typename // "") != "Bot" and ((.a.login // "") != $me or .alone)
                     and .t != null and .t > $since)
            ) as $act
          | "\($p.repository.nameWithOwner)#\($p.number)\t\(if $act then "comments" else "open" end)"' \
        </dev/null 2>/dev/null || true)"
    fi

    # Bash folds empty tab-separated fields together, so the query writes "~"
    # for an empty one, and it is turned back into an empty field here.
    while IFS=$'\t' read -r id status low type number repo subs linked title; do
      [ "$status" = "~" ] && status=""
      [ "$type" = "~" ] && type=""
      pr="-"
      stage_of "$low" "$type" "$number" "$subs"
      if [ -n "$stage" ]; then
        pr_for "$repo" "$number" "$linked"
        if [ "$found" != "-" ]; then
          pr="open"
          if [ "$stage" = "in review" ]; then
            pr="-"   # Unless call 3 answered for it: then there's no way to tell.
            while IFS=$'\t' read -r which state; do
              [ "$which" = "$found" ] && pr="$state"
            done <<< "$feedback"
          fi
        fi
      fi
      steps_for "$low" "$type" "${subs#*/}" "$pr"
      printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$id" "$status" "$type" "$number" "$repo" "$subs" "$steps" "$title"
    done <<< "$rows"
    ;;

  ""|-h|--help|help)
    # The comment block at the top of this file is the help text.
    awk 'NR == 1 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "$0"
    ;;

  *)
    die "unknown command: $cmd (try: $0 help)"
    ;;
esac
