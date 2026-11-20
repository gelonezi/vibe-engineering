---
name: review
description: Review code diffs for an In review item or pull request against the item's spec and repository standards, drafting comments into a local checklist file for selective posting. Use when reviewing code before approval.
---

# vibe-engineering:review

Reviews a Pull Request or **In review** board item against its `## Spec` and codebase
patterns. Rather than posting comments indiscriminately, it drafts an interactive
checklist file where the user picks exactly which comments to post. The flow is described
in [docs/concept.md](../../docs/concept.md).

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
2. Select item or PR:
   - If the user provided a PR number or link, use that PR directly.
   - Otherwise, list items in **In review**:
     ```bash
     bash scripts/projects.sh items <projectId> "In review"
     ```
     Ask the user which item or PR to review.

## 3. Fetch context and diff

1. Get the PR details:
   ```bash
   gh pr view <prNumber> --json number,title,body,headRefName,url,headRepository
   ```
2. Read the full git diff:
   ```bash
   gh pr diff <prNumber>
   ```
3. Read the board item body for the specification:
   ```bash
   bash scripts/projects.sh item-body <itemId>
   ```
   Focus on `## Spec`, acceptance criteria, and edge cases.

## 4. Conduct the Review

Analyze the diff systematically:
- **Spec Compliance:** Does the diff fulfill all requirements in `## Spec`? Is there missing functionality or scope creep?
- **Logic & Correctness:** Are there edge cases, off-by-one errors, or unhandled exceptions?
- **Testing:** Are there tests for all new behaviors? Do tests verify edge cases?
- **Maintainability & Patterns:** Does the code align with the rest of the repository (`CLAUDE.md`, idioms, typing, formatting)?

## 5. Draft the Review Checklist

**GitHub Rule:** GitHub blocks authors from formally approving or requesting changes
on their own PRs. All feedback is posted as constructive review comments.

1. Ensure the directory `.vibe/` exists:
   ```bash
   mkdir -p .vibe
   ```
   (Ensure `.vibe/` is added to `.git/info/exclude` or `.gitignore` so it is not committed).
2. Write a checklist file at `.vibe/review-<prNumber>.md`:
   ```markdown
   # Review Checklist for PR #<prNumber>

   Check the items (`- [x]`) you want to post to GitHub. Edit comment wording directly if needed.

   - [ ] `<filepath>:<line>`: <Proposed comment explaining the issue and suggestion>
   - [ ] `<filepath>:<line>`: <Proposed comment explaining the issue and suggestion>
   ```
3. Present the checklist to the user:
   Show the findings and tell them they can tick the boxes in `.vibe/review-<prNumber>.md`
   or tell you which ones to post.

## 6. Post Selected Comments

Once the user confirms or updates the checklist:
1. Parse the checklist file for all checked items (`- [x]`).
2. For each checked comment:
   Post the comment to the pull request:
   ```bash
   gh pr comment <prNumber> --body "<comment text>"
   ```
3. Delete the temporary checklist file:
   ```bash
   rm -f .vibe/review-<prNumber>.md
   ```

## 7. Report

Report in a few lines:
- Number of comments posted to PR `<prUrl>`
- Next steps:
  - If fixes are needed: `vibe-engineering:develop` will switch to the branch and
    move the item back to **In progress** to address the feedback.
  - If no changes are needed: `vibe-engineering:approve` to merge the PR and complete
    the item.
