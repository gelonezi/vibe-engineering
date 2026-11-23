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
# <pr> is what the item's open pull request says: "open", "comments" when a
# reviewer left feedback that no commit has answered yet, or "-" when none was
# found. `board` finds the pull request as the other skills do, by its branch
# `feature/<number>-<slug>`, and else by the "Closes <repo>#<number>" line push
# writes. Feedback is a review that requests changes or says something, an
# open review thread, or a comment on the pull request, from a person rather
# than a bot, made after the pull request's latest commit. A push that answers
# it makes the item "open" again until someone reviews it once more.
# "Fix comments" is offered for "comments", and for "-", when there is no way
# to tell. In progress says "Update the pull request" once one is open.
set -euo pipefail

die() { echo "ERROR: $*" >&2; exit 1; }

# Prints the steps for one item. Keep in step with docs/concept.md.
steps_for() {
  local status type total pr
  status="$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]')"
  type="${2:-ISSUE}"
  total="${3:-0}"
  pr="${4:--}"
  case "$total" in ''|*[!0-9]*) total=0 ;; esac

  if [ "$type" = "PULL_REQUEST" ] || [ "$total" -gt 0 ]; then
    echo "-"; return
  fi
  case "$status" in
    draft)         echo "promote-backlog:Design it" ;;
    backlog)       echo "promote-ready:Write the spec" ;;
    ready)         echo "develop:Build it" ;;
    "in progress")
      if [ "$pr" = "-" ]; then echo "push:Open the pull request"
      else echo "push:Update the pull request"; fi ;;
    "in review")
      if [ "$pr" = "open" ]; then echo "review:Review,approve:Merge"
      else echo "review:Review,develop:Fix comments,approve:Merge"; fi ;;
    *)             echo "-" ;;
  esac
}

cmd="${1:-}"; shift || true

case "$cmd" in
  steps)
    [ $# -ge 1 ] && [ $# -le 4 ] || die "usage: steps <status> [type] [subTotal] [pr]"
    steps_for "$@"
    ;;

  board)
    [ $# -eq 1 ] || die "usage: board <projectId>"
    # --paginate follows $endCursor, so boards with more than 100 items are read in full.
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
        (.type // "~"),
        (.content.number // "-"),
        (.content.repository.nameWithOwner // "-"),
        "\(.content.subIssuesSummary.completed // 0)/\(.content.subIssuesSummary.total // 0)",
        ([.content.closedByPullRequestsReferences.nodes[]? | select(.state == "OPEN")
          | "\(.repository.nameWithOwner)#\(.number)"] | first // "-"),
        (.content.title // "")
      ] | @tsv')"
    [ -n "$rows" ] || exit 0

    # The open pull requests of each repository with work in progress or in
    # review, read once per repository: "<repo>\t<headBranch>\t<number>" lines.
    open_prs=""
    seen_repos=" "
    prs_of() {
      case "$seen_repos" in *" $1 "*) return ;; esac
      seen_repos="$seen_repos$1 "
      open_prs="$open_prs$(gh api graphql -f o="${1%%/*}" -f n="${1#*/}" -f query='
        query($o: String!, $n: String!) {
          repository(owner: $o, name: $n) {
            pullRequests(states: OPEN, first: 100, orderBy: { field: UPDATED_AT, direction: DESC }) {
              nodes { number headRefName }
            }
          }
        }' --jq '.data.repository.pullRequests.nodes[]? | "'"$1"'\t\(.headRefName)\t\(.number)"' \
        </dev/null 2>/dev/null || true)
"
    }

    # Sets `found` to the issue's pull request, as "<repo>#<number>", or "-".
    # It sets a variable rather than printing, so the cache above survives.
    pr_for() {
      local repo="$1" number="$2" r head n
      found="$3"
      prs_of "$repo"
      while IFS=$'\t' read -r r head n; do
        [ "$r" = "$repo" ] || continue
        case "$head" in "feature/$number-"*) found="$r#$n"; return ;; esac
      done <<< "$open_prs"
    }

    # "comments" when a person left feedback after the latest commit, else "open".
    feedback_of() {
      local repo="${1%#*}" number="${1##*#}"
      gh api graphql -f o="${repo%%/*}" -f n="${repo#*/}" -F i="$number" -f query='
        query($o: String!, $n: String!, $i: Int!) {
          repository(owner: $o, name: $n) {
            pullRequest(number: $i) {
              commits(last: 1) { nodes { commit { committedDate } } }
              reviews(last: 50) { nodes { state body submittedAt author { __typename } } }
              reviewThreads(last: 100) {
                nodes { isResolved isOutdated comments(last: 1) { nodes { createdAt author { __typename } } } }
              }
              comments(last: 50) { nodes { createdAt author { __typename } } }
            }
          }
        }' \
        --jq '.data.repository.pullRequest as $p
          | ($p.commits.nodes[0].commit.committedDate // "") as $since
          | [ ($p.reviews.nodes[]
                | select(.author.__typename != "Bot")
                | select(.state == "CHANGES_REQUESTED" or (.state == "COMMENTED" and (.body // "") != ""))
                | .submittedAt),
              ($p.reviewThreads.nodes[]
                | select((.isResolved or .isOutdated) | not)
                | .comments.nodes[] | select(.author.__typename != "Bot") | .createdAt),
              ($p.comments.nodes[] | select(.author.__typename != "Bot") | .createdAt) ]
          | if any(.[]; . != null and . > $since) then "comments" else "open" end' \
        </dev/null 2>/dev/null || echo "-"
    }

    # Bash folds empty tab-separated fields together, so the query writes "~"
    # for an empty one, and it is turned back into an empty field here.
    while IFS=$'\t' read -r id status type number repo subs linked title; do
      [ "$status" = "~" ] && status=""
      [ "$type" = "~" ] && type=""
      pr="-"
      lower="$(printf '%s' "$status" | tr '[:upper:]' '[:lower:]')"
      if [ "$type" = "ISSUE" ] && [ "$number" != "-" ] && [ "${subs#*/}" = "0" ]; then
        case "$lower" in
          "in progress"|"in review")
            pr_for "$repo" "$number" "$linked"
            if [ "$found" != "-" ]; then
              pr="open"
              if [ "$lower" = "in review" ]; then pr="$(feedback_of "$found")"; fi
            fi
            ;;
        esac
      fi
      printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$id" "$status" "$type" "$number" "$repo" "$subs" \
        "$(steps_for "$status" "$type" "${subs#*/}" "$pr")" "$title"
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
