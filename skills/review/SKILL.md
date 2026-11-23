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

**Find the repository's guide first.** Claude Code reads a project's rules from
`CLAUDE.md` or from `.claude/CLAUDE.md`, so a repository may keep its guide in
either place. Run `bash scripts/guide.sh` in the repository. It prints the path
of each guide file, one per line, from the repository's top folder, and ends
with `GUIDES=<n>`:

- `CLAUDE.md`, `.claude/CLAUDE.md` or a file under `.claude/rules/`, with no
  folder before it, holds rules for the whole repository.
- The same names inside a folder, such as `packages/api/CLAUDE.md`, hold rules
  for that folder only. Keep the ones in a folder the PR changes, or in a
  folder above one.
- `GUIDES=0`: the repository has no guide. Say so in one sentence, and check
  *Fit* against its linters and the code around the change.
- It lists the files as they are on this computer. A guide that the PR itself
  adds, moves or changes is in the diff: read it there.
- If it prints an `ERROR:` line instead, show it, and look for those names in
  the repository yourself.

**The code on its own.** If `code-review:code-review` is available, run it on the
PR **without** `--comment`, so its findings come back to the chat instead of going
to GitHub. It uses several agents to look for definite bugs and breaks of the
repository's guide, and checks each finding before reporting it.

By itself it looks for a `CLAUDE.md` in the top folder and in the folders the PR
changes, so it can miss a guide kept in `.claude/`, and then checks the PR
against no rules at all. Tell it where the guide is. In the same request, after
the PR, give it the paths you kept above, and say that these are the
repository's `CLAUDE.md` files for its compliance check, together with any it
finds itself. For example, for PR 17:

> Pull request 17. The repository's guide files are `.claude/CLAUDE.md` and
> `packages/api/CLAUDE.md`. Treat each one as a CLAUDE.md file: put them on
> the list of CLAUDE.md files, and check the changes against them.

Give the paths exactly as `guide.sh` printed them. With `GUIDES=0`, give it
only the PR.

It stops by itself on a draft or closed PR, and on one Claude has already
commented on. If it stops, or isn't available, cover *Correctness* and *Fit*
below yourself.

**The code against the item.** That skill doesn't know the board, so *The spec* and
*Tests* below are always yours.

Go through the diff with these questions:

- **The spec:** does it do everything `## Spec` asks? Does it do things the spec
  doesn't ask for? Extra scope makes the PR harder to review and is worth naming.
- **Correctness:** edge cases, off-by-one errors, unhandled errors.
- **Tests:** is each new behavior tested, including the edge cases in the spec?
- **Fit:** does it follow the repository's own rules (the guide files you found
  above, linters) and the patterns of the code around it?

Only comment on lines the PR adds or changes. GitHub can't attach a comment to a
line outside the diff.

## 5. Draft the checklist

The user picks which comments go to GitHub, so they go to a file first, not
straight to the PR.

1. Make the folder for the checklist and keep it out of git, so the checklist
   is never committed: run `bash scripts/vibe-dir.sh`. It makes `.vibe` in the
   repository's top folder, makes sure git ignores it, and prints
   `VIBE_DIR=<path>`. If it prints an `ERROR:` line instead, show it and don't
   write the checklist: it could end up in a commit.
2. Write `review-<prNumber>.md` in that folder, which is
   `.vibe/review-<prNumber>.md` from the repository's top folder, with your
   findings and the ones from `code-review:code-review` in one list, without
   duplicates:
   ```markdown
   # Review of PR #<prNumber>

   Tick (`- [x]`) the comments to post. You can change the wording too.

   - [ ] `<path>:<line>`: <the problem, and what to do about it>
   - [ ] `<path>:<line>`: <the problem, and what to do about it>
   ```
3. Show the findings in the chat, and say the user can tick them in the file or
   just tell you which ones to post.

If the review found nothing at all, write no checklist. Say so, and go to
step 7: there is nothing to post.

## 6. Post the chosen comments

Posting is visible to everyone on the PR, so post only what the user picked.

1. Read the ticked items (`- [x]`) from the checklist, with any wording changes.

   **If no comment is picked** (nothing is ticked, and the user named none),
   post nothing. Don't write a payload and don't run `pr-review`. A review with
   only its text would keep **Fix comments** on in the board's side panel until
   the next commit, with nothing to fix. Delete `.vibe/review-<prNumber>.md`
   and go to step 7.
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

- how many comments were posted, with the review's link. If no comment was
  picked, say that no review was posted
- the next step:
  - fixes needed: `vibe-engineering:develop`, which goes back to the branch and
    moves the item to **In progress**
  - nothing to fix, or no review posted: `vibe-engineering:approve`, to merge
    and finish the item
