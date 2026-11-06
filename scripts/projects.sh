#!/usr/bin/env bash
# Small wrapper around the GitHub Projects (v2) GraphQL API, used by the
# vibe-engineering skills. Needs only the GitHub CLI (gh); no jq.
#
# Usage: projects.sh <command> [args]
#
#   whoami                              Login of the authenticated user
#   owner <login>                       "<id>\t<User|Organization>\t<login>"
#   orgs                                Organizations you belong to, one login per line
#   repo <owner/name>                   "<repoId>\t<ownerId>\t<ownerLogin>\t<ownerType>\t<yourPermission>"
#   find <ownerLogin> <title>           Projects with exactly this title:
#                                       "<number>\t<id>\t<public>\t<closed>\t<url>"
#   get <ownerLogin> <number>           "<id>\t<title>\t<public>\t<url>"
#   template                            The default template: "<id>\t<title>\t<public>\t<url>"
#   copy <ownerId> <projectId> <title>  Copy a project (no items): "<id>\t<number>\t<url>"
#   set-public <projectId> <true|false> Change visibility
#   link <projectId> <repoId>           Link the project to a repository
#   verify <projectId>                  JSON: views, fields, status options, iterations, repos
#   build <ownerId> <title>             Fallback: create the board from scratch (see create-board's references/board-spec.md)
#   board <link|name>                   The board the user named, by link or by name (any case, in your
#                                       account and organizations): "<number>\t<id>\t<title>\t<url>"
#   list <ownerLogin> [search]          Open projects of an owner: "<number>\t<id>\t<title>\t<url>"
#   draft-create <projectId> <title> <bodyFile>
#                                       Add a draft issue, body read from a file: "<itemId>"
#   set-status <projectId> <itemId> <status>
#                                       Set an item's Status by option name, prints the name read back
#   item-status <itemId>                Print an item's current Status
#
# Template settings (environment variables):
#   VIBE_ENGINEERING_TEMPLATE_OWNER   default: gelonezi
#   VIBE_ENGINEERING_TEMPLATE_NUMBER  default: 4
set -euo pipefail

TEMPLATE_OWNER="${VIBE_ENGINEERING_TEMPLATE_OWNER:-gelonezi}"
TEMPLATE_NUMBER="${VIBE_ENGINEERING_TEMPLATE_NUMBER:-4}"

die() { echo "ERROR: $*" >&2; exit 1; }
gql() { gh api graphql "$@"; }

cmd="${1:-}"; shift || true

case "$cmd" in
  whoami)
    gql -f query='query { viewer { login } }' --jq .data.viewer.login
    ;;

  owner)
    [ $# -eq 1 ] || die "usage: owner <login>"
    gql -f login="$1" -f query='
      query($login: String!) { repositoryOwner(login: $login) { id __typename login } }' \
      --jq '.data.repositoryOwner | if . == null then error("owner not found") else [.id, .__typename, .login] | @tsv end'
    ;;

  orgs)
    gql -f query='query { viewer { organizations(first: 100) { nodes { login } } } }' \
      --jq '.data.viewer.organizations.nodes[].login'
    ;;

  repo)
    [ $# -eq 1 ] || die "usage: repo <owner/name>"
    case "$1" in */*) ;; *) die "expected owner/name, got: $1" ;; esac
    gql -f o="${1%%/*}" -f n="${1#*/}" -f query='
      query($o: String!, $n: String!) {
        repository(owner: $o, name: $n) { id viewerPermission owner { id login __typename } }
      }' \
      --jq '.data.repository | if . == null then error("repository not found") else [.id, .owner.id, .owner.login, .owner.__typename, .viewerPermission] | @tsv end'
    ;;

  find)
    [ $# -eq 2 ] || die "usage: find <ownerLogin> <title>"
    title="$2"
    gql -f login="$1" -f q="$title" -f query='
      query($login: String!, $q: String!) {
        repositoryOwner(login: $login) {
          ... on User         { projectsV2(first: 50, query: $q) { nodes { title number id public closed url } } }
          ... on Organization { projectsV2(first: 50, query: $q) { nodes { title number id public closed url } } }
        }
      }' \
      --jq '.data.repositoryOwner.projectsV2.nodes[]? | [.title, .number, .id, .public, .closed, .url] | @tsv' \
    | awk -F'\t' -v t="$title" 'BEGIN { OFS = "\t" } $1 == t { print $2, $3, $4, $5, $6 }'
    ;;

  get)
    [ $# -eq 2 ] || die "usage: get <ownerLogin> <number>"
    gql -f login="$1" -F n="$2" -f query='
      query($login: String!, $n: Int!) {
        repositoryOwner(login: $login) {
          ... on User         { projectV2(number: $n) { id title public url } }
          ... on Organization { projectV2(number: $n) { id title public url } }
        }
      }' \
      --jq '.data.repositoryOwner.projectV2 | if . == null then error("project not found") else [.id, .title, .public, .url] | @tsv end'
    ;;

  template)
    bash "$0" get "$TEMPLATE_OWNER" "$TEMPLATE_NUMBER"
    ;;

  copy)
    [ $# -eq 3 ] || die "usage: copy <ownerId> <projectId> <title>"
    gql -f owner="$1" -f project="$2" -f title="$3" -f query='
      mutation($owner: ID!, $project: ID!, $title: String!) {
        copyProjectV2(input: { ownerId: $owner, projectId: $project, title: $title, includeDraftIssues: false }) {
          projectV2 { id number url }
        }
      }' \
      --jq '.data.copyProjectV2.projectV2 | [.id, .number, .url] | @tsv'
    ;;

  set-public)
    [ $# -eq 2 ] || die "usage: set-public <projectId> <true|false>"
    case "$2" in true|false) ;; *) die "visibility must be true or false" ;; esac
    gql -f id="$1" -F public="$2" -f query='
      mutation($id: ID!, $public: Boolean!) {
        updateProjectV2(input: { projectId: $id, public: $public }) { projectV2 { public } }
      }' \
      --jq '.data.updateProjectV2.projectV2.public'
    ;;

  link)
    [ $# -eq 2 ] || die "usage: link <projectId> <repoId>"
    gql -f p="$1" -f r="$2" -f query='
      mutation($p: ID!, $r: ID!) {
        linkProjectV2ToRepository(input: { projectId: $p, repositoryId: $r }) { repository { nameWithOwner } }
      }' \
      --jq '.data.linkProjectV2ToRepository.repository.nameWithOwner'
    ;;

  verify)
    [ $# -eq 1 ] || die "usage: verify <projectId>"
    gql -f id="$1" -f query='
      query($id: ID!) {
        node(id: $id) {
          ... on ProjectV2 {
            title number url public
            views(first: 30) { nodes { name layout filter } }
            fields(first: 50) {
              nodes {
                ... on ProjectV2FieldCommon { name dataType }
                ... on ProjectV2SingleSelectField { options { name color description } }
                ... on ProjectV2IterationField {
                  configuration { duration startDay iterations { title startDate duration } }
                }
              }
            }
            repositories(first: 10) { nodes { nameWithOwner } }
          }
        }
      }' \
      --jq '.data.node'
    ;;

  build)
    [ $# -eq 2 ] || die "usage: build <ownerId> <title>"
    # Best effort: each step reports OK or FAILED and the build carries on.
    created="$(gql -f owner="$1" -f title="$2" -f query='
      mutation($owner: ID!, $title: String!) {
        createProjectV2(input: { ownerId: $owner, title: $title }) { projectV2 { id number url } }
      }' --jq '.data.createProjectV2.projectV2 | [.id, .number, .url] | @tsv')"
    IFS=$'\t' read -r pid pnum purl <<<"$created"
    echo "CREATED	$pid	$pnum	$purl"

    step() { # step <label> <graphql mutation using $p>
      if out="$(gql -f p="$pid" -f query="$2" 2>&1 >/dev/null)"; then
        echo "OK	$1"
      else
        echo "FAILED	$1	$(printf '%s' "$out" | tr '\n' ' ')"
      fi
    }

    status_id="$(gql -f p="$pid" -f query='
      query($p: ID!) { node(id: $p) { ... on ProjectV2 { field(name: "Status") { ... on ProjectV2SingleSelectField { id } } } } }' \
      --jq '.data.node.field.id' 2>/dev/null || true)"
    if [ -n "$status_id" ]; then
      if out="$(gql -f f="$status_id" -f query='
        mutation($f: ID!) {
          updateProjectV2Field(input: { fieldId: $f, singleSelectOptions: [
            { name: "Draft",       color: GRAY,   description: "This idea is still growing" },
            { name: "Backlog",     color: GREEN,  description: "This item hasn'"'"'t been started" },
            { name: "Ready",       color: BLUE,   description: "This is ready to be picked up" },
            { name: "In progress", color: YELLOW, description: "This is actively being worked on" },
            { name: "In review",   color: PURPLE, description: "This item is in review" },
            { name: "Done",        color: ORANGE, description: "This has been completed" }
          ] }) { projectV2Field { ... on ProjectV2SingleSelectField { id } } }
        }' 2>&1 >/dev/null)"; then
        echo "OK	Status options"
      else
        echo "FAILED	Status options	$(printf '%s' "$out" | tr '\n' ' ')"
      fi
    else
      echo "FAILED	Status options	Status field not found"
    fi

    step "Priority field" '
      mutation($p: ID!) { createProjectV2Field(input: { projectId: $p, dataType: SINGLE_SELECT, name: "Priority", singleSelectOptions: [
        { name: "P0", color: RED,    description: "" },
        { name: "P1", color: ORANGE, description: "" },
        { name: "P2", color: YELLOW, description: "" }
      ] }) { clientMutationId } }'

    step "Size field" '
      mutation($p: ID!) { createProjectV2Field(input: { projectId: $p, dataType: SINGLE_SELECT, name: "Size", singleSelectOptions: [
        { name: "XS", color: BLUE,   description: "" },
        { name: "S",  color: GREEN,  description: "" },
        { name: "M",  color: YELLOW, description: "" },
        { name: "L",  color: ORANGE, description: "" },
        { name: "XL", color: RED,    description: "" }
      ] }) { clientMutationId } }'

    step "Estimate field" 'mutation($p: ID!) { createProjectV2Field(input: { projectId: $p, dataType: NUMBER, name: "Estimate" }) { clientMutationId } }'

    today="$(date +%Y-%m-%d)"
    step "Iteration field" "
      mutation(\$p: ID!) { createProjectV2Field(input: { projectId: \$p, dataType: ITERATION, name: \"Iteration\",
        iterationConfiguration: { startDate: \"$today\", duration: 14, iterations: [] } }) { clientMutationId } }"

    echo "VIEWS	manual	This script does not create views: set them up by hand, see references/board-spec.md"
    ;;

  board)
    [ $# -eq 1 ] || die "usage: board <link|name>"
    case "$1" in
      *://*)
        # https://github.com/orgs/<login>/projects/<n> or .../users/<login>/projects/<n>, with or without a view
        case "$1" in
          */orgs/*/projects/[0-9]*|*/users/*/projects/[0-9]*) ;;
          *) die "not a link to a GitHub Projects board: $1" ;;
        esac
        login="$(printf '%s' "$1" | sed -E 's#.*/(orgs|users)/([^/]+)/projects/.*#\2#')"
        number="$(printf '%s' "$1" | sed -E 's#.*/projects/([0-9]+).*#\1#')"
        line="$(bash "$0" get "$login" "$number")"
        IFS=$'\t' read -r id title _ url <<<"$line"
        printf '%s\t%s\t%s\t%s\n' "$number" "$id" "$title" "$url"
        ;;
      *)
        for login in "$(bash "$0" whoami)" $(bash "$0" orgs); do
          bash "$0" list "$login" "$1" | awk -F'\t' -v t="$1" 'tolower($3) == tolower(t)' || true
        done
        ;;
    esac
    ;;

  list)
    [ $# -ge 1 ] && [ $# -le 2 ] || die "usage: list <ownerLogin> [search]"
    gql -f login="$1" -f q="${2:-}" -f query='
      query($login: String!, $q: String!) {
        repositoryOwner(login: $login) {
          ... on User         { projectsV2(first: 50, query: $q) { nodes { number id title url closed } } }
          ... on Organization { projectsV2(first: 50, query: $q) { nodes { number id title url closed } } }
        }
      }' \
      --jq '.data.repositoryOwner.projectsV2.nodes[]? | select(.closed | not) | [.number, .id, .title, .url] | @tsv'
    ;;

  draft-create)
    [ $# -eq 3 ] || die "usage: draft-create <projectId> <title> <bodyFile>"
    [ -f "$3" ] || die "body file not found: $3"
    # -F body=@file reads the body from the file, so quotes and newlines survive.
    gql -f p="$1" -f t="$2" -F body=@"$3" -f query='
      mutation($p: ID!, $t: String!, $body: String) {
        addProjectV2DraftIssue(input: { projectId: $p, title: $t, body: $body }) { projectItem { id } }
      }' \
      --jq '.data.addProjectV2DraftIssue.projectItem.id'
    ;;

  set-status)
    [ $# -eq 3 ] || die "usage: set-status <projectId> <itemId> <status>"
    status_line="$(gql -f p="$1" -f query='
      query($p: ID!) {
        node(id: $p) { ... on ProjectV2 { field(name: "Status") { ... on ProjectV2SingleSelectField { id options { id name } } } } }
      }' \
      --jq '.data.node.field | .id as $f | .options[] | [$f, .id, .name] | @tsv' \
      | awk -F'\t' -v s="$3" '$3 == s { print $1 "\t" $2; exit }')"
    [ -n "$status_line" ] || die "this board's Status field has no option named: $3"
    IFS=$'\t' read -r status_field status_option <<<"$status_line"
    gql -f p="$1" -f i="$2" -f f="$status_field" -f o="$status_option" -f query='
      mutation($p: ID!, $i: ID!, $f: ID!, $o: String!) {
        updateProjectV2ItemFieldValue(input: { projectId: $p, itemId: $i, fieldId: $f, value: { singleSelectOptionId: $o } }) { clientMutationId }
      }' >/dev/null
    bash "$0" item-status "$2"
    ;;

  item-status)
    [ $# -eq 1 ] || die "usage: item-status <itemId>"
    gql -f i="$1" -f query='
      query($i: ID!) {
        node(id: $i) { ... on ProjectV2Item { fieldValueByName(name: "Status") { ... on ProjectV2ItemFieldSingleSelectValue { name } } } }
      }' \
      --jq '.data.node.fieldValueByName.name // ""'
    ;;

  ""|-h|--help|help)
    sed -n '2,31p' "$0" | sed 's/^# \{0,1\}//'
    ;;

  *)
    die "unknown command: $cmd (try: $0 help)"
    ;;
esac
