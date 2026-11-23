---
name: push
description: Push the current branch, open or update its pull request linked to the vibe-engineering board item, and move the item to In review. Use when the user says push it, open a PR, create the pull request or send it for review, or the code for a board item is committed and ready. Use this rather than a plain git push when the work belongs to an item on the board.
---

# vibe-engineering:push

Pushes the active branch, creates or updates the Pull Request linked to the board item,
and moves the item from **In progress** to **In review**. The flow is described in
[docs/concept.md](../../docs/concept.md).

Every GitHub call goes through the scripts in the plugin's `scripts/` folder. Run them
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
per match: `<number>\t<id>\t<title>\t<public>\t<url>`. Keep the project's ID and URL.

## 3. Identify the item and branch

1. Check the current branch with `git branch --show-current`. If it's the
   repository's default branch, stop: the work belongs on the item's own branch,
   which `vibe-engineering:develop` creates.
2. Check that everything is committed:
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

**Column check:** the item should be in **In progress**. If it's somewhere else,
say where, and ask before moving it on, since it may have skipped a step.

## 4. Push the branch

Push the branch to origin:
```bash
git push -u origin <branch>
```

## 5. Open or update the pull request

1. Check whether the branch already has an open PR:
   `bash scripts/repo.sh pr-for-branch <branch>`. It prints
   `<number>  <url>`, or nothing.
2. **If there's one:** the push in step 4 already added the new commits to it.
   Tell the user, with its link, and go on to step 6, which is only for this case.
3. **If there's none:**
   - Read the item with `bash scripts/projects.sh item <itemId>` for its issue
     number, repository and title.
   - Draft the description. Write the issue as `<owner/name>#<issueNumber>`: a
     bare `#<n>` only closes the issue when it's in the same repository as the PR.
     ```markdown
     Closes <owner/name>#<issueNumber>

     ### Overview
     (What changed and why, following the item's spec)

     ### Verification
     - (The tests and checks you ran, and their result)

     Board item: <boardUrl>
     ```
   - Show the title and description, and change them until the user agrees.
     The PR is visible to everyone who can see the repository.
   - Write the description to a new temporary file (`mktemp`), then run
     `bash scripts/repo.sh pr-create "<title>" <bodyFile>`. It prints the PR's
     link. Delete the file afterwards. Skip step 6: a pull request opened
     just now has no fixed threads.

## 6. Resolve the review threads that were fixed

Only for a pull request that was already open before this push.

When `vibe-engineering:develop` fixes review comments, it writes the IDs of the
threads it fixed to `.vibe/fixed-threads-<prNumber>.txt`, in the repository's
top folder, one per line. They are resolved here and not there, because only
now is the fix on the pull request.

1. If that file isn't there, skip this step.
2. Check that the fix is on the pull request: `git rev-parse HEAD` and
   `git rev-parse '@{u}'` must print the same commit. If they don't, the push
   did not send everything. Tell the user, leave the file where it is, and
   skip the rest of this step.
3. Run `bash scripts/repo.sh pr-threads <prNumber>`. It prints each open review
   thread as `<threadId>\t<path>\t<line>\t<author>\t<firstComment>` and ends
   with `THREADS=<n>`. Keep the rows whose ID is in the file. An ID from the
   file that isn't among the rows is no longer an open thread: leave it alone,
   and say how many there were. Pass a `WARN` line on in one sentence.
4. If no row is left, delete the file and go on to step 7.
5. List the rows by path, line and comment, and ask the user once whether to
   mark them resolved on GitHub. They can pick only some. Resolving is visible
   on the pull request.
6. For each one they confirm, run
   `bash scripts/repo.sh resolve-thread <threadId>`, which prints
   `RESOLVED=true`. If it fails, it prints one `ERROR:` line and nothing else.
   This command is safe to run again, so try that thread once more. If it
   fails again, show the line, leave the thread open and carry on with the
   others.
7. Delete the file, whatever the user answered. If they said no, nothing is
   resolved.

The board's side panel offers **Fix comments** until every thread is resolved.
A review that requested changes stays in force until its reviewer reviews
again, whatever is resolved.

## 7. Move the item to In review

Run `bash scripts/projects.sh set-status <projectId> <itemId> "In review"`. It
prints the status it reads back. Board workflows can also move items, so if it
isn't `In review`, tell the user what the board shows.

## 8. Report

Report in a few lines:
- Pull Request URL (`<prUrl>`) and branch name
- The review threads marked resolved in step 6, and any left open
- Linked issue and board item status: **In review**
- Next step:
  - `vibe-engineering:review` to generate a selective review checklist.
  - `vibe-engineering:approve` when checks pass and you are ready to merge.
