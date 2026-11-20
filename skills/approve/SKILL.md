---
name: approve
description: Merge a reviewed pull request for a vibe-engineering board item after checking its checks, conflicts and review status, then close a finished parent issue and move the item to Done. Use when the user says approve, merge, ship it, land it or finish an item, or an item in In review is ready to merge. Always asks before merging.
---

# vibe-engineering:approve

Verifies pull request health, confirms with the user, merges the pull request, and
moves the board item from **In review** to **Done**. Merging cannot be undone, so this
skill always verifies and asks first. The flow is described in
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

## 2. Find the board and item

1. Board resolution:
   The user must tell you which board to use: its link, or its board, panel or
   project name. If they haven't, ask and wait.
   Run `bash scripts/projects.sh board "<what they told you>"`.
2. Select the item:
   If the user named an item or a pull request, use it. Otherwise, list the items in
   **In review**:
   ```bash
   bash scripts/projects.sh items <projectId> "In review"
   ```
   Show the list and ask which item to approve and merge.
3. Find its pull request. If the user gave a PR, use it. Otherwise the branch that
   `vibe-engineering:develop` made is `feature/<issueNumber>-<slug>`: find it with
   `git branch -r --list 'origin/feature/<issueNumber>-*'`, then run
   `bash scripts/repo.sh pr-for-branch <branch>`. If there's no match, ask the user
   for the PR.

## 3. Check the pull request

Run `bash scripts/repo.sh pr <prNumber>`. It prints
`<number>  <state>  <isDraft>  <mergeable>  <mergeStateStatus>  <reviewDecision>  <headBranch>  <baseBranch>  <url>  <title>`.

- `state` isn't `OPEN`: say so and stop. It may already be merged or closed.
- `mergeable` is `CONFLICTING`: stop. The conflicts have to be fixed on the branch
  first, which `vibe-engineering:develop` can do.
- `isDraft` is `true`: say so. GitHub won't merge a draft until it's marked ready.
- `reviewDecision` is `CHANGES_REQUESTED`: name it, and ask whether the comments
  were dealt with before going on. `REVIEW_REQUIRED` means branch protection wants
  an approval that isn't there yet, and GitHub will block the merge. Report it, and
  don't try to get round it. `NONE` means no review rule applies.

Then run `bash scripts/repo.sh checks <prNumber>`. Its last line is `CHECKS=...`:

- `fail`: list the failing checks, and ask whether to look into them instead.
- `pending`: say which are still running, and ask whether to wait.
- `pass` or `none`: carry on. With `none`, tell the user the repository has no
  automated checks, so nothing tested this PR on GitHub.

## 4. Confirm with the user

A merge can't be undone, so never merge without a clear yes for this PR. Show:

- the PR's title, number and link
- the checks and the review status, in one line each
- the merge method you'll use (see step 5)

Then ask, for example: *"PR #<number> is ready. Shall I merge it and move the item
to Done?"* Wait for the answer.

## 5. Merge

1. Pick the merge method. Run `bash scripts/repo.sh merge-settings`, which prints
   `<defaultBranch>  <squashAllowed>  <mergeAllowed>  <rebaseAllowed>`. Use `squash`
   when it's allowed, since one item is one commit on the default branch. Otherwise
   use the one allowed method, or ask if several are.
2. Merge: `bash scripts/repo.sh merge <prNumber> <method>`. This also deletes the
   branch.
3. Bring the local copy up to date, if the user is in that repository and has no
   uncommitted changes: `git checkout <defaultBranch> && git pull`.

## 6. Close a finished parent issue

Run `bash scripts/repo.sh issue-parent <owner/name> <issueNumber>`. If it prints
nothing, the item has no parent, so skip this step. Otherwise it prints
`<parentNumber>  <parentState>  <completedSubIssues>  <totalSubIssues>`.

If the parent is still `OPEN` and every sub-issue is completed, ask:
*"All the sub-issues of #<parentNumber> are done. Shall I close it as well?"* On a
yes, run `bash scripts/repo.sh issue-close <owner/name> <parentNumber>`.

## 7. Move the item to Done

The board's *Pull request merged* workflow usually does this on its own. Set it
anyway, so the result doesn't depend on the workflow being on:

```bash
bash scripts/projects.sh set-status <projectId> <itemId> Done
```

It prints the status it reads back. If it isn't `Done`, tell the user what it shows.

## 8. Report

Report in a few lines:

- the merged PR, as a link, and the method used
- that the branch was deleted
- the item's status: **Done**, and the parent issue if you closed it
- that the item has finished the whole flow, from idea to merged code
