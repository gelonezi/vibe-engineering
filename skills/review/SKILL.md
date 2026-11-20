---
name: review
description: Review a pull request for a vibe-engineering board item against the item's spec and the repository's standards, draft inline comments in a checklist, and post only the ones the user picks. Use when the user asks to review a PR, check a pull request or look over the changes for an item, or says something like "review PR 17", and the PR belongs to an item on the board.
---

# vibe-engineering:review

Reviews a Pull Request or **In review** board item against its `## Spec` and codebase
patterns. Rather than posting comments indiscriminately, it drafts an interactive
checklist file where the user picks exactly which comments to post. The flow is described
in [docs/concept.md](../../docs/concept.md).

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
2. Select the item or PR:
   - If the user gave a PR number or link, use that PR, and find its item from
     the `Closes` line in the PR's description.
   - Otherwise, list the items in **In review**:
     ```bash
     bash scripts/projects.sh items <projectId> "In review"
     ```
     Ask which one to review. Its PR is on the branch `feature/<issueNumber>-<slug>`:
     find it with `git branch -r --list 'origin/feature/<issueNumber>-*'` and
     `bash scripts/repo.sh pr-for-branch <branch>`, or ask the user for it.

## 3. Read the PR and the spec

1. `bash scripts/repo.sh pr <prNumber>`: its state, branches, link and title.
2. `bash scripts/repo.sh pr-body <prNumber>`: what the author says it does.
3. `bash scripts/repo.sh pr-diff <prNumber>`: the changes.
4. `bash scripts/projects.sh item-body <itemId>`: the item. The `## Spec` section,
   with its acceptance criteria and edge cases, is what the PR is measured against.

## 4. Review

The review has two halves: the code on its own, and the code against the item.

**The code on its own.** If `code-review:code-review` is available, run it on the
PR **without** `--comment`, so its findings come back to the chat instead of going
to GitHub. It uses several agents to look for definite bugs and breaks of the
repository's `CLAUDE.md`, and checks each finding before reporting it. It stops by
itself on a draft or closed PR, and on one Claude has already commented on. If it
stops, or isn't available, cover *Correctness* and *Fit* below yourself.

**The code against the item.** That skill doesn't know the board, so *The spec* and
*Tests* below are always yours.

Go through the diff with these questions:

- **The spec:** does it do everything `## Spec` asks? Does it do things the spec
  doesn't ask for? Extra scope makes the PR harder to review and is worth naming.
- **Correctness:** edge cases, off-by-one errors, unhandled errors.
- **Tests:** is each new behavior tested, including the edge cases in the spec?
- **Fit:** does it follow the repository's own rules (`CLAUDE.md`, linters) and the
  patterns of the code around it?

Only comment on lines the PR adds or changes. GitHub can't attach a comment to a
line outside the diff.

## 5. Draft the checklist

The user picks which comments go to GitHub, so they go to a file first, not
straight to the PR.

1. Create the folder and keep it out of git, so the checklist is never committed:
   ```bash
   mkdir -p .vibe
   grep -qxF '.vibe/' .git/info/exclude 2>/dev/null || echo '.vibe/' >> .git/info/exclude
   ```
2. Write `.vibe/review-<prNumber>.md`, with your findings and the ones from
   `code-review:code-review` in one list, without duplicates:
   ```markdown
   # Review of PR #<prNumber>

   Tick (`- [x]`) the comments to post. You can change the wording too.

   - [ ] `<path>:<line>`: <the problem, and what to do about it>
   - [ ] `<path>:<line>`: <the problem, and what to do about it>
   ```
3. Show the findings in the chat, and say the user can tick them in the file or
   just tell you which ones to post.

## 6. Post the chosen comments

Posting is visible to everyone on the PR, so post only what the user picked.

1. Read the ticked items (`- [x]`) from the checklist, with any wording changes.
2. Write them to a new temporary file (`mktemp`) as one review, in GitHub's format:
   ```json
   {
     "event": "COMMENT",
     "body": "Review from vibe-engineering: <n> comments.",
     "comments": [
       { "path": "<path>", "line": <line>, "side": "RIGHT", "body": "<comment>" }
     ]
   }
   ```
   `event` is always `COMMENT`: GitHub doesn't let authors approve or request
   changes on their own PRs, and the decision to merge belongs to
   `vibe-engineering:approve`.
3. Post it: `bash scripts/repo.sh pr-review <prUrl> <payloadFile>`. It prints the
   review's link. If GitHub rejects a line, it's outside the diff: move that
   comment into the review's `body` and post again.
4. Delete the temporary file and `.vibe/review-<prNumber>.md`.

## 7. Report

Report in a few lines:

- how many comments were posted, with the review's link
- the next step:
  - fixes needed: `vibe-engineering:develop`, which goes back to the branch and
    moves the item to **In progress**
  - nothing to fix: `vibe-engineering:approve`, to merge and finish the item
