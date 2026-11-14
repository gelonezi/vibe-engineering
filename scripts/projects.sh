#!/usr/bin/env bash
# Small wrapper around GitHub Projects (v2), used by the vibe-engineering
# skills. It uses the GitHub CLI's own "gh project" commands where they exist,
# and the GraphQL API for the rest. Needs only gh; no jq.
#
# Usage: projects.sh <command> [args]
#
#   whoami                              Login of the authenticated user
#   owner <login>                       "<id>\t<User|Organization>\t<login>"
#   owners                              Where you can own a board, your account first:
#                                       "<login>\t<User|Organization>\t<canCreateProjects>"
#   orgs                                Organizations you belong to, one login per line
#   repos <ownerLogin>                  The owner's repositories you can link a board to, most
#                                       recently pushed first: "<owner/name>\t<yourPermission>"
#   repo <owner/name|link>              "<repoId>\t<ownerId>\t<ownerLogin>\t<ownerType>\t<yourPermission>\t<owner/name>"
#   find <ownerLogin> <title>           Projects with exactly this title:
#                                       "<number>\t<id>\t<public>\t<closed>\t<url>"
#   get <ownerLogin> <number>           "<id>\t<title>\t<public>\t<url>"
#   template                            The default template: "<id>\t<title>\t<public>\t<url>"
#   copy <ownerLogin> <title>           Copy the template (no items) to that owner: "<id>\t<number>\t<url>"
#   set-public <ownerLogin> <number> <true|false>
#                                       Change visibility, prints the value read back
#   link <ownerLogin> <number> <owner/name>
#                                       Link the project to a repository of the same owner, so it shows
#                                       on the repo's Projects tab. Prints the repository. It can't set
#                                       the project's "Default repository": GitHub has no API for that.
#   verify <projectId>                  JSON: views, fields, status options, workflows, repos
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
#   VIBE_ENGINEERING_TEMPLATE_NUMBER  default: 6
set -euo pipefail

TEMPLATE_OWNER="${VIBE_ENGINEERING_TEMPLATE_OWNER:-gelonezi}"
TEMPLATE_NUMBER="${VIBE_ENGINEERING_TEMPLATE_NUMBER:-6}"

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

  owners)
    gql -f query='query { viewer { login organizations(first: 100) { nodes { login viewerCanCreateProjects } } } }' \
      --jq '.data.viewer | ([.login, "User", "true"] | @tsv), (.organizations.nodes[] | [.login, "Organization", (.viewerCanCreateProjects | tostring)] | @tsv)'
    ;;

  orgs)
    gql -f query='query { viewer { organizations(first: 100) { nodes { login } } } }' \
      --jq '.data.viewer.organizations.nodes[].login'
    ;;

  repos)
    [ $# -eq 1 ] || die "usage: repos <ownerLogin>"
    # Linking needs write access, so read-only repositories are left out.
    gh repo list "$1" --no-archived --limit 50 --json nameWithOwner,viewerPermission \
      --jq '.[] | select(.viewerPermission == "ADMIN" or .viewerPermission == "MAINTAIN" or .viewerPermission == "WRITE") | [.nameWithOwner, .viewerPermission] | @tsv'
    ;;

  repo)
    [ $# -eq 1 ] || die "usage: repo <owner/name|link>"
    # Accepts owner/name, or a link to the repository or to any page inside it.
    slug="$(printf '%s' "$1" | sed -E 's#^[a-z]+://[^/]+/##; s#^/+##; s#\.git$##')"
    case "$slug" in
      orgs/*|users/*) die "this is a link to an account or a board, not to a repository: $1" ;;
      */*) ;;
      *) die "expected owner/name or a repository link, got: $1" ;;
    esac
    repo_owner="${slug%%/*}"; repo_name="${slug#*/}"; repo_name="${repo_name%%/*}"
    gql -f o="$repo_owner" -f n="$repo_name" -f query='
      query($o: String!, $n: String!) {
        repository(owner: $o, name: $n) { id nameWithOwner viewerPermission owner { id login __typename } }
      }' \
      --jq '.data.repository | if . == null then error("repository not found") else [.id, .owner.id, .owner.login, .owner.__typename, .viewerPermission, .nameWithOwner] | @tsv end'
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
    [ $# -eq 2 ] || die "usage: copy <ownerLogin> <title>"
    # Views, fields and workflows come with the copy. Items don't.
    gh project copy "$TEMPLATE_NUMBER" --source-owner "$TEMPLATE_OWNER" --target-owner "$1" --title "$2" \
      --format json --jq '[.id, .number, .url] | @tsv'
    ;;

  set-public)
    [ $# -eq 3 ] || die "usage: set-public <ownerLogin> <number> <true|false>"
    case "$3" in true) visibility=PUBLIC ;; false) visibility=PRIVATE ;; *) die "visibility must be true or false" ;; esac
    gh project edit "$2" --owner "$1" --visibility "$visibility" --format json --jq '.public'
    ;;

  link)
    [ $# -eq 3 ] || die "usage: link <ownerLogin> <number> <owner/name>"
    # gh prints nothing useful when it isn't on a terminal, so confirm here.
    gh project link "$2" --owner "$1" --repo "$3" >/dev/null
    echo "$3"
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
              }
            }
            workflows(first: 20) { nodes { name enabled } }
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
        { name: "XS", color: GREEN,  description: "" },
        { name: "S",  color: PURPLE, description: "" },
        { name: "M",  color: RED,    description: "" },
        { name: "L",  color: YELLOW, description: "" },
        { name: "XL", color: PINK,   description: "" }
      ] }) { clientMutationId } }'

    step "Estimate field" 'mutation($p: ID!) { createProjectV2Field(input: { projectId: $p, dataType: NUMBER, name: "Estimate" }) { clientMutationId } }'
    step "Start date field" 'mutation($p: ID!) { createProjectV2Field(input: { projectId: $p, dataType: DATE, name: "Start date" }) { clientMutationId } }'
    step "Target date field" 'mutation($p: ID!) { createProjectV2Field(input: { projectId: $p, dataType: DATE, name: "Target date" }) { clientMutationId } }'

    echo "VIEWS	manual	This script does not create views or workflows: set them up by hand, see references/board-spec.md"
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
    # The comment block at the top of this file is the help text.
    awk 'NR == 1 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "$0"
    ;;

  *)
    die "unknown command: $cmd (try: $0 help)"
    ;;
esac
