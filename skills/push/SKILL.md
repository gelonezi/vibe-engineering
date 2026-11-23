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
   Tell the user, with its link. Then check that its title and description
   are still true, as "Keep the title and description true" below says, and
   go on to step 6, which is only for this case.
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

### Keep the title and description true

Only for a pull request that was already open before this push. Its title and
description were written for an earlier version of the branch. After a review
fix, or after the base branch was merged in, they can say things that no
longer hold. `vibe-engineering:approve` uses the title for the merge commit,
so a stale one ends up in the history.

1. Read the pull request: `bash scripts/repo.sh pr <prNumber>` prints one row
   with the base branch in the 8th column and the title in the 10th. A
   backslash in the title is printed twice in that row.
   `bash scripts/repo.sh pr-body <prNumber>` prints the description.
2. Read what the branch holds now: the item, with
   `bash scripts/projects.sh item <itemId>` and
   `bash scripts/projects.sh item-body <itemId>`, then
   `git log --oneline origin/<base>..HEAD` and
   `git diff --stat origin/<base>...HEAD`.
3. Check each statement in the title and the description against that. What
   usually goes out of date: a release or version number, a file, command or
   behaviour that a later commit changed, a test result from before the last
   commit, and a part of the work the description doesn't mention.
4. **If all of it is still true,** say so in one sentence and change nothing.
5. **If not,** write the new title and description:
   - Keep every line that is still true as it was written, and anything a
     person added by hand.
   - Keep the `Closes <owner/name>#<issueNumber>` line and the `Board item:`
     line exactly as they are. The `Closes` line links the pull request to
     its issue.
   - Show the new title and description in full, with a short list of what
     changed, and ask before changing anything. The pull request is visible to
     everyone who can see the repository.
6. **When the user agrees,** write the title to one new temporary file and the
   description to another. Write them with your file tool, not through a shell
   command, so that quotes, backticks and dollar signs stay as they are. The
   title file holds one line. Then run
   `bash scripts/repo.sh pr-edit <prNumber> <titleFile> <bodyFile>`. It sets
   both and prints `UPDATED=<prUrl>`. Delete the two files afterwards.
7. If it fails, it prints one `ERROR:` line and nothing is changed.
   - If the line says the description drops a `Closes` line, put that line
     back in the description and run the command again.
   - For any other failure, the command is safe to run again, so try once
     more. If it fails again, show the line, leave the title and description
     as they are, and carry on: the new commits are on the pull request
     either way.
8. **If the user says no,** change nothing and carry on.

Then go on to step 6, the review threads.

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

Resolving the threads turns **Fix comments** off in the board's side panel
only when nothing else keeps it on. The button also shows while a reviewer's
latest verdict requests changes, and after a review with only text or other
text from someone else, until the next commit. A review that requested changes
stays in force until its reviewer reviews again, whatever is resolved. The
whole rule is in [docs/concept.md](../../docs/concept.md), under "The side
panel guides, only".

## 7. Move the item to In review

Run `bash scripts/projects.sh set-status <projectId> <itemId> "In review"`. It
prints the status it reads back. Board workflows can also move items, so if it
isn't `In review`, tell the user what the board shows.

## 8. Report

Report in a few lines:
- Pull Request URL (`<prUrl>`) and branch name
- For a pull request that was already open: whether its title and description
  were still true, were updated, or were left as they are
- The review threads marked resolved in step 6, and any left open
- Linked issue and board item status: **In review**
- Next step:
  - `vibe-engineering:review` to generate a selective review checklist.
  - `vibe-engineering:approve` when checks pass and you are ready to merge.
