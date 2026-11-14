---
name: create-board
description: Create a GitHub Projects board for the vibe-engineering flow (Draft, Backlog, Ready, In progress, In review and Done columns, with Priority, Size, Estimate and views such as Backlog, Priority board, Roadmap and My items). Use when the user wants to create, set up, copy or bootstrap a GitHub project board, planner or kanban, for their account, an organization, or a repository.
---

# vibe-engineering:create-board

Creates a GitHub Projects board by copying a public template project, then sets
its visibility and, if asked, links it to a repository.
The board is specified in [references/board-spec.md](references/board-spec.md).

Every GitHub call goes through two scripts in the plugin's `scripts/` folder.
Run them with `bash <skill-dir>/../../scripts/<name>.sh`; the steps below
shorten that to `bash scripts/<name>.sh`. Never guess IDs, logins or numbers:
get each one from a script's output.

## 1. Check GitHub access

Run `bash scripts/check-auth.sh` and read its `KEY=value` lines.

- `STATUS=ok`: continue with step 2, and keep `LOGIN`.
- `STATUS=projects_unavailable`: this session can't reach GitHub Projects at
  all, which is the case in Claude Code cloud sessions. Don't show the `FIX`
  line and don't suggest a token. Go to
  [In a cloud session](#in-a-cloud-session).
- Any other status: stop. Show the user the `FIX` line as a command they can
  run, explain it in one sentence, and offer to run the check again once
  they've done it. Don't try to work around it.
- Pass any `WARN` lines on in one sentence each, and continue.

## 2. Ask where the board goes

GitHub projects belong to a **user** or an **organization**. There is no
repository-owned project. A "repository board" is a project owned by the
repository's owner and linked to the repository, so it shows on the repo's
*Projects* tab.

Ask two questions, one at a time. Use the AskUserQuestion tool if you have it,
so the user picks from a list. Offer every choice the scripts return. If there
are more than the tool can show, show the first ones, which are the most
recently used, and say the user can type any other.

**If the user already said where** (a repository as `owner/name` or as a link,
or an account name), don't ask what they've answered. For a repository, run
`bash scripts/projects.sh repo <owner/name or link>`: it gives the owner's
login and type, your permission, and the `owner/name`. Then apply the checks
under question B.

### Question A: the owner

Run `bash scripts/projects.sh owners`. Each line is
`<login>  <User|Organization>  <canCreateProjects>`, your own account first.

Offer the user's own account, then each organization where the third column is
`true`. If an organization shows `false`, leave it out, and mention it only if
the user asks for it: they need the organization's permission to create
projects. You can only create a board for the account you're logged in as or
for an organization, never for another user.

### Question B: whole account or one repository

Run `bash scripts/projects.sh repos <ownerLogin>`. Each line is
`<owner/name>  <yourPermission>`, most recently pushed first.

Offer, in this order:

1. **No repository.** A board for the whole account or organization, which can
   hold items from any of its repositories.
2. Each repository from the list. The board is linked to it and shows on its
   *Projects* tab.

GitHub only links a board to a repository with the same owner, which is why
the list comes from the owner chosen in question A. If the user typed a
repository that isn't in the list, run `projects.sh repo` on it:

- If its owner is another user's account, you can't create a board there.
  Offer a board in the user's own account instead, without a link.
- If the permission is `READ` or empty, warn that linking will probably fail
  (it needs write access), and ask whether to continue.

## 3. Ask for the name and visibility

- **Project name.** Suggest `Planner`, and use whatever the user picks.
- **Visibility.** Private (the default) or public.

Then check for a name clash with `bash scripts/projects.sh find <ownerLogin> "<name>"`.
If it prints anything, a project with that exact name already exists. Show its
URL and ask the user to pick: a different name, open the existing one, or stop.
Don't create a duplicate without asking.

## 4. Create the board

1. Check the template: `bash scripts/projects.sh template`.
   It prints `<id>  <title>  <public>  <url>`.
2. Copy it: `bash scripts/projects.sh copy <ownerLogin> "<name>"`.
   It prints `<id>  <number>  <url>`. Views, fields and workflows come with
   the copy. Items don't. Never run `copy` a second time for the same board:
   it would create a duplicate.
3. Set the visibility you agreed on. Copies start out private, so run this
   only for public: `bash scripts/projects.sh set-public <ownerLogin> <number> true`.
4. For a repository board:
   `bash scripts/projects.sh link <ownerLogin> <number> <owner/name>`.
   It prints the repository when the link is made. The board now shows on the
   repository's *Projects* tab.

Linking doesn't set the board's **Default repository**, which is where new
issues created from the board go, and GitHub has no API for it. For a
repository board, tell the user to set it by hand, in step 5.

If `template` or `copy` fails (the template was deleted, made private, or
can't be reached, or the user may not create projects for that owner), tell
the user why, and offer the fallback in step 6. Don't fall back silently.

## 5. Verify and report

Run `bash scripts/projects.sh verify <projectId>` and compare its output with
[references/board-spec.md](references/board-spec.md): the views, the Status
options, the custom fields, the workflows, and the linked repository.

Report in a few lines:

- the board's URL, as a link
- the owner, visibility, and linked repository (if any)
- anything that doesn't match the spec, and what the user should do about it
- for a repository board, the one step left for the user: open
  `<board url>/settings`, and under **Default repository** pick the
  repository. Give the settings page as a link.

## 6. Fallback: build from scratch

Use this only after the user agrees to it in step 4.

1. Get the owner's ID with `bash scripts/projects.sh owner <ownerLogin>`, then
   run `bash scripts/projects.sh build <ownerId> "<name>"`. It creates the
   project and its fields, and prints one `OK` or `FAILED` line per step.
2. Apply the visibility and repository link from step 4, with the number from
   the `CREATED` line.
3. Show any `FAILED` steps, with the fix for each from the spec.
4. The script doesn't create views or workflows. Give the user the manual
   steps in the spec's *Creating views by hand* section, or offer to walk them
   through.

## In a cloud session

Use this section only when step 1 reported `STATUS=projects_unavailable`.

Tell the user, in one or two sentences, that this session can't create or read
GitHub Projects boards, and that a different token wouldn't change it. Then
ask which they prefer, with the AskUserQuestion tool if you have it:

- **Continue in Claude Code on my computer** (recommended). The skill does
  everything there.
- **Make the copy myself on GitHub.** A few clicks, guided from here.

Don't try any other route, such as GitHub's REST API or an MCP server: this
session's GitHub access covers single repositories, not boards.

### Continue in Claude Code on their computer

Tell the user to:

1. Open Claude Code on their computer. If the plugin isn't installed there:

   ```
   /plugin marketplace add gelonezi/vibe-engineering
   /plugin install vibe-engineering@vibe-engineering
   ```

2. Call this skill again there: `/vibe-engineering:create-board`, or just ask
   to create a board.

Say what will happen there, so they know what to expect: the skill asks where
the board goes (their account or one of their organizations), whether it's for
the whole account or linked to one repository, and its name and visibility,
and then creates it. Then stop. Don't ask those questions here: the answers
can't be carried to the other session.

### Make the copy themselves

The template board is `https://github.com/users/gelonezi/projects/6`, unless
the settings at the end of this file name another one. Don't run
`projects.sh template` here: it can't reach GitHub Projects either. Give the
user these steps, with the template as a link:

1. Open the template board.
2. Click the **⋯** menu at the top right of the board, then **Make a copy**.
3. Leave *Draft issues will be copied if selected* unticked.
4. Under **Owner**, choose your own account or one of your organizations.
5. Under **New project name**, type the board's name. `Planner` is a good one.
6. Click **Copy project**.

#### Connect the board to a repository

Always raise this topic after the copy: ask whether the board is for the whole
account or for one repository. For one repository, give these steps:

1. In the new board, open the **⋯** menu, then **Settings**.
2. Under **Default repository**, pick the repository. New issues created from
   the board are then added to it. The list only shows repositories of the
   board's owner.
3. Open that repository on GitHub and go to its **Projects** tab. If the board
   isn't listed there, click **Link a project** and pick it.

For a board for the whole account, say that nothing more is needed: items from
any of the owner's repositories can be added to it.

#### Make it public

Offer this only if the user wants a public board. Copies start out private. In
the board, open **⋯**, then **Settings**, and change **Visibility** in the
*Danger zone*.

#### Finish

- Ask for the new board's link, and repeat it back so the user has it at hand
  for the other skills.
- Say plainly that you can't check the board from this session, and give the
  checklist to check by eye: six columns in the order Draft, Backlog, Ready,
  In progress, In review, Done; and the views Backlog, Priority board, Team
  items, Roadmap and My items.
- Say that the other board skills, starting with
  `vibe-engineering:create-item`, also need Claude Code on their computer for
  now.

## Settings

The template can be changed with environment variables:

- `VIBE_ENGINEERING_TEMPLATE_OWNER` (default `gelonezi`)
- `VIBE_ENGINEERING_TEMPLATE_NUMBER` (default `6`)
- `GH_HOST` (for GitHub Enterprise Server)
