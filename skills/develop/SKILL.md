---
name: develop
description: Build a feature or fix from a Ready or In review board item on a branch, following the repository's own rules and the item's spec as its sole context. Use when picking up a Ready item to develop, or an In review item to address comments.
---

# vibe-engineering:develop

Takes an item from **Ready** (or an **In review** item with review comments to address)
and moves it to **In progress** while writing the code on a git branch. The flow is
described in [docs/concept.md](../../docs/concept.md).

Every GitHub call goes through scripts in the plugin's `scripts/` folder. Run them
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
project name. If they haven't, ask and wait. Never choose one yourself.

Run `bash scripts/projects.sh board "<what they told you>"`. It prints one line
per match: `<number>\t<id>\t<title>\t<url>`. Keep the project's ID and URL.

## 3. Select the item

If the user specified an item (by title, issue number, or link), find it.
If not, list items currently in **Ready** and **In review**:

```bash
bash scripts/projects.sh items <projectId> Ready
bash scripts/projects.sh items <projectId> "In review"
```

Show the list and ask the user which item to work on.

**Column check:**
The item should be in **Ready** (new work) or **In review** (addressing feedback).
If it is in any other status (e.g. `Draft` or `Backlog`), warn the user:
> *"This item is currently in **<status>**. Development starts from **Ready** (after specification and sizing) or **In review** (to fix comments). Shall I proceed anyway?"*

Wait for confirmation before continuing.

## 4. Read the item — The Single Source of Truth

**Golden Rule:** The item is the only context. Read:
1. `bash scripts/projects.sh item <itemId>`
2. `bash scripts/projects.sh item-body <itemId>`

Extract:
- `## Idea`: Understanding the user's intent.
- `## High-level design`: Understanding the architectural decisions and boundaries.
- `## Spec`: The exact requirements, affected files, edge cases, and test plan.

If working on an **In review** item to address feedback, also inspect the open review
comments or the checklist file from `vibe-engineering:review`.

## 5. Prepare the git branch

1. Check current repository status:
   ```bash
   git status --porcelain
   ```
   If uncommitted changes exist, stop and ask the user how they want to handle them.
2. Determine branch name:
   - **From Ready (new work):** Create and switch to a new branch:
     `git checkout -b feature/<issueNumber>-<short-slug>`
   - **From In review (revising work):** Switch to the existing branch for that PR.
3. Move board item to **In progress**:
   ```bash
   bash scripts/projects.sh set-status <projectId> <itemId> "In progress"
   ```
   Verify with `bash scripts/projects.sh item-status <itemId>`.

## 6. Implement the Spec

Follow the target repository's own standards and conventions:
- Consult project guidelines (`CLAUDE.md`, `.github/CONTRIBUTING.md`, linter configs, or README).
- Implement only what is required by `## Spec`. Avoid scope creep.
- Follow existing patterns in the codebase (naming, error handling, architecture).
- Write automated unit and/or integration tests for all changes, covering the acceptance
  criteria in `## Spec`.

## 7. Verify locally

Run the repository's test and lint suites (e.g., `npm test`, `pytest`, `cargo test`,
`dotnet test`). Ensure:
- All new tests pass.
- No existing tests are broken.
- Linters and code formatters pass cleanly.

## 8. Commit and Report

1. Stage and commit changes with a descriptive message referencing the issue:
   `git commit -m "feat: <summary> (#<issueNumber>)"`
2. Report in a few lines:
   - Branch name and commits created
   - Tests and checks verified
   - Current board item status: **In progress**
   - Next step: `vibe-engineering:push` to push the branch and open or update the PR.
