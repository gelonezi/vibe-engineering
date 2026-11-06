---
name: create-board
description: Create a GitHub Projects board for iterative development (Draft, Backlog, Ready, In progress, In review, Done columns, plus iterations, estimates and views like Current iteration, Next iteration, Prioritized backlog, Roadmap, In review, My items). Use when the user wants to create, set up or bootstrap a GitHub project board, planner, kanban, sprint or iteration board, for their account, an organization, or a repository.
---

# vibe-engineering:create-board

Creates a GitHub Projects board by copying the public **Iterative development**
template, then sets its visibility and, if asked, links it to a repository.
The board is specified in [references/board-spec.md](references/board-spec.md).

Every GitHub call goes through two scripts in the plugin's `scripts/` folder.
Run them with `bash <skill-dir>/../../scripts/<name>.sh`; the steps below
shorten that to `bash scripts/<name>.sh`. Never guess IDs: get each one from a
script's output.

## 1. Check GitHub access

Run `bash scripts/check-auth.sh` and read its `KEY=value` lines.

- `STATUS=ok`: continue, and keep `LOGIN` for step 2.
- Any other status: stop. Show the user the `FIX` line as a command they can
  run, explain it in one sentence, and offer to run the check again once
  they've done it. Don't try to work around it.
- Pass any `WARN` lines on in one sentence each, and continue.

## 2. Ask where the board goes

GitHub projects belong to a **user** or an **organization**. There is no
repository-owned project. A "repository board" is a project owned by the
repository's owner and linked to the repository, so it shows on the repo's
*Projects* tab.

Ask the user, with the AskUserQuestion tool if you have it:

- **My account** (`LOGIN` from step 1). You can only create projects for the
  account you're logged in as, never for another user.
- **An organization.** List the choices with `bash scripts/projects.sh orgs`.
  If it lists nothing, ask for the organization's login.
- **A repository** (`owner/name`). Then run `bash scripts/projects.sh repo <owner/name>`:
  - If the owner type is `User` and the owner isn't `LOGIN`, you can't create a
    project there. Offer to create the board in the user's own account instead,
    without a link. GitHub only links projects and repositories that have the
    same owner.
  - If the permission is `READ` or empty, warn that linking will probably fail
    (it needs write access), and ask whether to continue.

Get the owner's ID with `bash scripts/projects.sh owner <login>`. For a
repository, `repo` already returned it.

## 3. Ask for the name and visibility

- **Project name.** Suggest `Planner`, and use whatever the user picks.
- **Visibility.** Private (the default) or public.

Then check for a name clash with `bash scripts/projects.sh find <ownerLogin> "<name>"`.
If it prints anything, a project with that exact name already exists. Show its
URL and ask the user to pick: a different name, open the existing one, or stop.
Don't create a duplicate without asking.

## 4. Create the board

1. Find the template: `bash scripts/projects.sh template`.
   It prints `<id>  <title>  <public>  <url>`.
2. Copy it: `bash scripts/projects.sh copy <ownerId> <templateId> "<name>"`.
   It prints `<id>  <number>  <url>`. Fields, views and board settings come
   with the copy. Items don't.
3. Set the visibility you agreed on. Copies start out private, so run this
   only for public: `bash scripts/projects.sh set-public <projectId> true`.
4. For a repository board: `bash scripts/projects.sh link <projectId> <repoId>`.

If `template` or `copy` fails (the template was deleted, made private, or
can't be reached), tell the user why, and offer the fallback in step 6.
Don't fall back silently.

## 5. Verify and report

Run `bash scripts/projects.sh verify <projectId>` and compare its output with
[references/board-spec.md](references/board-spec.md): the views, the Status
options, the custom fields, and the linked repository.

Check the Iteration field: if none of its iterations covers today
(`startDate <= today < startDate + duration days`), the **Current iteration**
view will be empty. Tell the user to fix it in *Settings → Iteration*, and
offer to give them the steps.

Report in a few lines:

- the board's URL, as a link
- the owner, visibility, and linked repository (if any)
- anything that doesn't match the spec, and what the user should do about it

## 6. Fallback: build from scratch

Use this only after the user agrees to it in step 4.

1. Run `bash scripts/projects.sh build <ownerId> "<name>"`. It creates the
   project and its fields, and prints one `OK` or `FAILED` line per step.
2. Apply the visibility and repository link from step 4.
3. Show any `FAILED` steps, with the fix for each from the spec.
4. The script doesn't create views. Give the user the manual steps in the
   spec's *Creating views by hand* section, or offer to walk them through.

## Settings

The template can be changed with environment variables:

- `VIBE_ENGINEERING_TEMPLATE_OWNER` (default `gelonezi`)
- `VIBE_ENGINEERING_TEMPLATE_TITLE` (default `Iterative development`)
- `VIBE_ENGINEERING_TEMPLATE_NUMBER` (optional; looks the project up by number instead of by title)
- `GH_HOST` (for GitHub Enterprise Server)
