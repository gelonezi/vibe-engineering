---
name: promote-backlog
description: Write the high-level design (HLD) for a Draft item on the vibe-engineering GitHub Projects board and move it to Backlog, turning a draft into a real issue when needed. Use when the user wants to design, architect or plan the approach for an idea, says something like "let's design the stock idea" or "move it to the backlog", or an item in Draft is ready for design. Covers the architecture only, not the detailed spec or the code.
---

# vibe-engineering:promote-backlog

Helps the user take an item from **Draft** to **Backlog** by producing its High-Level
Design (HLD). The item carries its own context forward, as described in
[docs/concept.md](../../docs/concept.md).

Every GitHub call goes through the scripts in the plugin's `scripts/` folder. Run them
with `bash <skill-dir>/../../scripts/<name>.sh`; the steps below shorten that to
`bash scripts/<name>.sh`. Never guess IDs: get each one from a script's output.

## 1. Check GitHub access

Run `bash scripts/check-auth.sh` and read its `KEY=value` lines.

- `STATUS=ok`: continue.
- Any other status: stop. Show the user the `FIX` line as a command they can run,
  explain it in one sentence, and offer to run the check again once they've done it.
  Don't try to work around it.
- Pass any `WARN` lines on in one sentence each, and continue.

## 2. Find the board

The user must tell you which board to use: its link, or its board, panel or
project name. If they haven't, ask and wait. Never choose one yourself, whether
from the current repository, an earlier run or the only board you can find.

Run `bash scripts/projects.sh board "<what they told you>"`. It prints one line
per match: `<number>\t<id>\t<title>\t<public>\t<url>`.

- **One match:** use it, and name it in your report.
- **Several matches:** the same name exists under different owners. Show their
  URLs and ask which one.
- **No match, or an error:** tell the user, and ask them to check the name or
  send the link. If they want to see their boards, run
  `bash scripts/projects.sh list <ownerLogin>`.

Keep the project's ID and URL for the next steps.

## 3. Select the item

If the user named an item (by title, issue number, or link), find it on the board.
If they haven't specified an item, list the items currently in the **Draft** column:

```bash
bash scripts/projects.sh items <projectId> Draft
```

It outputs lines formatted as:
`<itemId>\t<status>\t<type>\t<number>\t<repo>\t<title>\t<contentId>`

Show the list to the user and ask which item they would like to design and promote.

**Column check:**
Once an item is selected, inspect its status. If its status is not `Draft`, warn the
user:
> *"This item is currently in **<status>**, not **Draft**. Do you want to proceed with writing its high-level design and moving it to Backlog?"*

Wait for their confirmation before continuing.

## 4. Inspect the item and assign repository

1. Inspect item details:
   ```bash
   bash scripts/projects.sh item <itemId>
   ```
2. Read the full body:
   ```bash
   bash scripts/projects.sh item-body <itemId>
   ```

**Content check:**
Verify that the body contains a `## Idea` section. If missing, warn the user:
> *"This item does not have a `## Idea` section yet. Earlier context may be missing. Should we draft an Idea section first or continue?"*

**Convert Draft Issue to Real Issue:**
Check the `<type>` field from `item <itemId>`:
- If `<type>` is `Issue`, it is already a repository issue. Continue to Step 5.
- If `<type>` is `DraftIssue`, it has no issue number or repository yet. To link pull
  requests and sub-issues, it must become a real GitHub issue:
  1. Determine the destination repository:
     - If the user is currently working inside a git repository that belongs to the
       board's owner, suggest that repository.
     - Otherwise, list available repositories with `bash scripts/projects.sh repos <ownerLogin>`
       and ask the user which repository this feature belongs to.
  2. Confirm with the user:
     > *"To move this item to Backlog, it will be converted into an issue in `<owner/repo>`. Shall I proceed?"*
  3. Resolve repository ID:
     ```bash
     bash scripts/projects.sh repo <owner/repo>
     ```
     (Read the `<repoId>` from the first column).
  4. Convert the draft issue:
     ```bash
     bash scripts/projects.sh convert-draft <itemId> <repoId>
     ```
     This outputs `<itemId>\t<issueNumber>\t<issueUrl>`. Use this `itemId` from
     now on, and keep the number and link for the report.

     Run it once. If it fails, run `bash scripts/projects.sh item <itemId>` before
     trying again: if the type is now `Issue`, the conversion went through, and a
     second run would fail or create confusion.

## 5. Shape the high-level design

The high-level design translates the idea into the software's architecture before
diving into task-level specifications.

1. **Read the software:**
   Read the repository's docs, architecture diagrams, directory structure, core models,
   and related existing components.
2. **Analyze architecture and trade-offs:**
   - Which components, modules, or services need to be changed or created?
   - What data models, schemas, or database migrations are required?
   - What API contracts, interfaces, or CLI flags are involved?
   - What are the architectural trade-offs, security implications, and error cases?
   - Are there open technical questions that must be resolved?
3. **Choose the approach with the user:**
   If `superpowers:brainstorming` is available, use it for this conversation. It
   lays out the possible approaches with their trade-offs and has the user pick
   one, which is what a high-level design needs. Two things change here, because
   the board is the memory:
   - The design goes in the item's `## High-level design` section (step 7), not
     in a file under `docs/`.
   - Stop once the user approves the design. Don't go on to
     `superpowers:writing-plans`: the spec belongs to
     `vibe-engineering:promote-ready`.

   If it isn't available, lay out the approaches yourself, say which one you
   would pick and why, and let the user choose.
4. **Format the HLD section:**
   The HLD section starts with `## High-level design`, and any headings inside it
   start at `###`. Each skill owns one `##` section, and later skills find theirs
   by its heading, so a stray `##` would split the design in two.

   Leave the `## Idea` section exactly as it is, and add the HLD below it. The idea
   is the user's own record of what they asked for, and later steps check the work
   against it.

   Example structure:
   ```markdown
   ## High-level design

   ### Architectural overview
   (Summary of components involved and data flow)

   ### Components & modules
   - `service/stock`: (role and changes)
   - `api/v1/endpoints`: (role and changes)

   ### Data model changes
   (Entities, schemas, migrations)

   ### Technical decisions & trade-offs
   (Choices made and why alternative options were ruled out)

   ### Open technical questions
   (Any architectural unknowns to resolve during detailed specification)
   ```

## 6. Confirm with the user

Show the proposed `## High-level design` to the user in full. Talk through any
trade-offs or architectural alternatives. Continue refining until the user approves.

## 7. Update the item and move to Backlog

1. Prepare the updated body:
   Combine the untouched `## Idea` content and the new `## High-level design` content.
   Write it to a new temporary file made with `mktemp`, so two runs never share one.
2. Update the item body:
   ```bash
   bash scripts/projects.sh item-update-body <itemId> <tempBodyFile>
   ```
3. Move status to Backlog:
   ```bash
   bash scripts/projects.sh set-status <projectId> <itemId> Backlog
   ```
   It prints the status it reads back. If it isn't `Backlog`, tell the user: board
   workflows can move items too.
4. Delete the temporary file.

## 8. Report

Report concisely:
- Issue number, title, and link (`<issueUrl>`)
- Board URL and current status: **Backlog**
- Next step: `vibe-engineering:promote-ready` when ready to write the detailed spec,
  estimate effort, and size the work into a single pull request.
