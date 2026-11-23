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
#   steps <status> [type] [subTotal]    The steps alone, for one item: "<steps>"
#
# <steps> is a comma-separated list of "<skill>:<label>", in the order to offer
# them, or "-" when nothing is started from here: a Done item, an item with no
# status, a pull request added to the board, or a parent whose sub-issues carry
# the work. <type> is DRAFT_ISSUE, ISSUE or PULL_REQUEST, and <number> and
# <repo> are "-" for a draft issue. Labels never hold a comma or a colon.
set -euo pipefail

die() { echo "ERROR: $*" >&2; exit 1; }

# Prints the steps for one item. Keep in step with docs/concept.md.
steps_for() {
  local status type total
  status="$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]')"
  type="${2:-ISSUE}"
  total="${3:-0}"
  case "$total" in ''|*[!0-9]*) total=0 ;; esac

  if [ "$type" = "PULL_REQUEST" ] || [ "$total" -gt 0 ]; then
    echo "-"; return
  fi
  case "$status" in
    draft)         echo "promote-backlog:Design it" ;;
    backlog)       echo "promote-ready:Write the spec" ;;
    ready)         echo "develop:Build it" ;;
    "in progress") echo "push:Open the pull request" ;;
    "in review")   echo "review:Review,develop:Fix comments,approve:Merge" ;;
    *)             echo "-" ;;
  esac
}

cmd="${1:-}"; shift || true

case "$cmd" in
  steps)
    [ $# -ge 1 ] && [ $# -le 3 ] || die "usage: steps <status> [type] [subTotal]"
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
                  ... on Issue { number title repository { nameWithOwner } subIssuesSummary { total completed } }
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
        (.content.title // "")
      ] | @tsv')"
    [ -n "$rows" ] || exit 0
    # Bash folds empty tab-separated fields together, so the query writes "~"
    # for an empty one, and it is turned back into an empty field here.
    while IFS=$'\t' read -r id status type number repo subs title; do
      [ "$status" = "~" ] && status=""
      [ "$type" = "~" ] && type=""
      printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$id" "$status" "$type" "$number" "$repo" "$subs" \
        "$(steps_for "$status" "$type" "${subs#*/}")" "$title"
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
