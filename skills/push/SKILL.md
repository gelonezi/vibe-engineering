---
name: push
description: Push the current feature branch to GitHub, open or update a Pull Request linked to the board item, and move the item to In review. Use when code changes are committed and ready for pull request creation and code review.
---

# vibe-engineering:push

Pushes the active branch, creates or updates the Pull Request linked to the board item,
and moves the item from **In progress** to **In review**. The flow is described in
[docs/concept.md](../../docs/concept.md).

Every GitHub call goes through scripts in the plugin's `scripts/` folder. Run them
with `bash <skill-dir>/../../scripts/<name>.sh`; the steps below shorten that to
`bash scripts/<name>.sh`. Never guess IDs: get each one from a script's output.

## 1. Check GitHub access

Run `bash scripts/check-auth.sh` and read its `KEY=value` lines.

- `STATUS=ok`: continue.
- Any other status: stop. Show the user the `FIX` line as a command they can run,
  explain it in one sentence, and offer to run the check again once they've done it.
- Pass any `WARN` lines on in one sentence each, and continue.

## 2. Find the board

The user must tell you which board to use: its link, or its board, panel or
project name. If they haven't, ask and wait. Never choose one yourself.

Run `bash scripts/projects.sh board "<what they told you>"`. It prints one line
per match: `<number>\t<id>\t<title>\t<url>`. Keep the project's ID and URL.

## 3. Identify the item and branch

1. Check current git branch:
   ```bash
   current_branch="$(git branch --show-current)"
   ```
2. Verify clean git working tree:
   ```bash
   git status --porcelain
   ```
   If uncommitted changes exist, stop and ask the user to commit or stash them first.
3. Identify the board item:
   - If the user specified an item, select it.
   - If the current branch name references an issue (e.g. `feature/12-stock`), search
     for that issue on the board.
   - Otherwise, list items in **In progress**:
     ```bash
     bash scripts/projects.sh items <projectId> "In progress"
     ```
     Ask the user which item this branch belongs to.

**Column check:**
Ensure the item is in **In progress**. If not, ask the user before moving it forward.

## 4. Push the branch

Push the branch to origin:
```bash
git push -u origin "$current_branch"
```

## 5. Create or update the Pull Request

1. Check if a PR already exists for this branch:
   ```bash
   existing_pr="$(gh pr list --head "$current_branch" --json number,url --jq '.[0] // empty')"
   ```
2. **If no PR exists:**
   - Read the item summary to get the issue number and title:
     `bash scripts/projects.sh item <itemId>`
   - Draft a clear PR description:
     ```markdown
     Closes #<issueNumber>

     ### Overview
     (Clear summary of the changes and files modified per the spec)

     ### Verification
     - (List test suites executed and passing)

     Board item: <itemUrl>
     ```
   - Ask user for confirmation on PR title and description before creating.
   - Create PR:
     ```bash
     gh pr create --title "<PR title>" --body-file <tempBodyFile>
     ```
3. **If PR already exists:**
   - Inform the user that new commits were pushed to the existing PR URL.

## 6. Update board status to In review

1. Move item to In review:
   ```bash
   bash scripts/projects.sh set-status <projectId> <itemId> "In review"
   ```
2. Verify status readback:
   `bash scripts/projects.sh item-status <itemId>`.
   If it is not `In review`, report what the board shows.

## 7. Report

Report in a few lines:
- Pull Request URL (`<prUrl>`) and branch name
- Linked issue and board item status: **In review**
- Next step:
  - `vibe-engineering:review` to generate a selective review checklist.
  - `vibe-engineering:approve` when checks pass and you are ready to merge.
