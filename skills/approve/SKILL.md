---
name: approve
description: Verify PR checks and mergeability, ask for explicit confirmation, merge the PR, close parent issues if all sub-issues are finished, and move the item to Done on your GitHub Projects board. Use when a reviewed pull request is ready to merge.
---

# vibe-engineering:approve

Verifies pull request health, confirms with the user, merges the pull request, and
moves the board item from **In review** to **Done**. Merging cannot be undone, so this
skill always verifies and asks first. The flow is described in
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

## 2. Find the board and item

1. Board resolution:
   The user must tell you which board to use: its link, or its board, panel or
   project name. If they haven't, ask and wait.
   Run `bash scripts/projects.sh board "<what they told you>"`.
2. Select item:
   If the user specified an item or PR number, use it. Otherwise, list items in
   **In review**:
   ```bash
   bash scripts/projects.sh items <projectId> "In review"
   ```
   Show the list and ask which item to approve and merge.

## 3. Audit PR status and CI checks

1. Retrieve PR mergeability and status:
   ```bash
   gh pr view <prNumber> --json number,title,state,mergeable,mergeStateStatus,url
   ```
   - If `mergeable` is `CONFLICTING`: stop. Explain that merge conflicts exist and
     must be resolved first on the branch.
2. Check automated CI checks:
   ```bash
   gh pr checks <prNumber>
   ```
   - If checks are failing: report failing checks and ask if the user wants to investigate.
   - If checks are still running: inform the user and ask if they wish to wait.
3. Check branch protection:
   If branch protection requires external approvals from another team member and
   none exist, GitHub will block the merge. Report this clearly without trying to
   bypass it.

## 4. Confirm with the user

**Golden Rule:** Merging cannot be undone. Always ask before merging.

Show the user:
- PR title, number, and URL
- Summary of CI check results
- Prompt:
  > *"All checks have passed and PR #<number> is ready to merge. Should I merge it now and move the board item to Done?"*

Wait for explicit confirmation.

## 5. Merge the Pull Request

Once confirmed:
1. Merge the pull request (using repository default or squash merge, deleting branch):
   ```bash
   gh pr merge <prNumber> --squash --delete-branch
   ```
2. Pull latest main branch locally to keep the local repo in sync:
   ```bash
   git checkout main && git pull
   ```

## 6. Parent Issue Check (Sub-issues)

If the item was a sub-issue:
1. Inspect the parent issue to see if all sub-issues are now closed.
2. If all sub-issues of the parent are closed, inform the user:
   > *"All sub-issues for parent issue #<parentNumber> are now complete. Would you like me to close the parent issue as well?"*
3. If confirmed, close the parent issue:
   ```bash
   gh issue close <parentNumber>
   ```

## 7. Update board status to Done

1. Move the item to **Done**:
   ```bash
   bash scripts/projects.sh set-status <projectId> <itemId> Done
   ```
2. Verify status readback:
   `bash scripts/projects.sh item-status <itemId>`.

## 8. Report

Report concisely:
- Merged PR URL and commit
- Feature branch deleted
- Item status: **Done**
- Completion celebration: the feature has completed the full Vibe Engineering delivery cycle!
