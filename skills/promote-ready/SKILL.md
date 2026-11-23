---
name: promote-ready
description: Write the detailed spec for a Backlog item on the vibe-engineering GitHub Projects board, set its Size and Estimate, split it into sub-issues until each one is a single pull request, and move it to Ready. Use when the user wants to spec, specify, size, estimate, break down, split or get an item ready for development, or says something like "get the stock item ready". Not for writing the code.
---

# vibe-engineering:promote-ready

Helps the user take an item from **Backlog** to **Ready** by writing its concrete
specification (`## Spec`), setting its `Size` and `Estimate`, and enforcing the core
rule: **One Ready item equals one pull request**. The flow is described in
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
- **Several matches:** show their URLs and ask which one.
- **No match, or an error:** tell the user, and ask them to check the name or
  send the link. If they want to see their boards, run
  `bash scripts/projects.sh list <ownerLogin>`.

Keep the project's ID and URL for the next steps.

## 3. Select the item

If the user named an item (by title, issue number, or link), find it on the board.
If they haven't specified an item, list the items currently in the **Backlog** column:

```bash
bash scripts/projects.sh items <projectId> Backlog
```

It outputs lines formatted as:
`<itemId>\t<status>\t<type>\t<number>\t<repo>\t<title>\t<contentId>`

Show the list to the user and ask which item they would like to specify and promote.

**Column check:**
Once an item is selected, inspect its status. If its status is not `Backlog`, warn the
user:
> *"This item is currently in **<status>**, not **Backlog**. Do you want to proceed with specifying it and moving it to Ready?"*

Wait for their confirmation before continuing.

## 4. Inspect the item

1. Inspect item details:
   ```bash
   bash scripts/projects.sh item <itemId>
   ```
2. Read the full body:
   ```bash
   bash scripts/projects.sh item-body <itemId>
   ```

**Content check:**
Verify that the body contains both an `## Idea` section and an `## High-level design`
section. If either is missing, warn the user:
> *"This item is missing earlier sections (`## Idea` or `## High-level design`). Each step builds on the last. Should we run the earlier step first or continue?"*

Wait for their confirmation.

## 5. Shape the spec, the size and any split

A specification tells `vibe-engineering:develop` exactly what to build and how to
verify it. It leaves no ambiguity about files, interfaces, acceptance criteria, or tests.

### 5.1. One Ready item is one pull request
Evaluate the scope against the single pull request standard:
- Can this feature be built, tested, and reviewed safely in a single PR (ideally < 400 lines of diff)?
- If yes: keep it as a single item.
- If no (the work spans independent layers, migrations, or large sub-features): **split it into sub-issues**.

### 5.2. Size and estimate
- **Size**: Assign one of `XS`, `S`, `M`, `L`, `XL`.
  - `XS`: Tiny tweak, config change, typo, 1-2 lines.
  - `S`: Small bugfix or localized component update (~under 100 lines).
  - `M`: Standard feature slice or endpoint with tests (~100-300 lines).
  - `L`: Significant feature requiring careful review (~300-500 lines).
  - `XL`: Almost certainly needs splitting. If keeping as XL, explain why.
- **Estimate**: story points, as a number from `1`, `2`, `3`, `5`, `8` or `13`. Points
  measure effort relative to other items, not hours. The board adds them up in each
  column, so a mix of points and hours would make those totals meaningless.

### 5.3. GitHub's length limit
GitHub issue bodies have a limit of ~65,000 characters. Check the character count of
the existing body plus proposed spec. If the total exceeds 50,000 characters, warn the
user and recommend splitting the item into sub-issues to avoid truncation.

### 5.4. What the spec contains
The spec section begins with `## Spec`, and any headings inside it start at `###`,
because later skills find each section by its `##` heading. Leave `## Idea` and
`## High-level design` exactly as they are: they record what was asked and decided,
and the review checks the work against them.

```markdown
## Spec

### Scope & files affected
- `src/services/warehouse.ts`: add `getWarehouseStock()`
- `src/controllers/stock.ts`: accept optional warehouse filter

### Detailed requirements & edge cases
- (Precise business rules and validation)
- (Error handling and status codes)

### Acceptance criteria & test plan
- [ ] Unit test: warehouse stock calculation with multi-location records
- [ ] Integration test: API returns 400 when invalid warehouse ID is supplied
```

## 6. Confirm with the user

Show the proposed `## Spec`, the assigned `Size`, and the `Estimate`.
- If splitting into sub-issues, outline the child items, their individual titles,
  specs, sizes, and estimates.
Refine with the user until they approve.

## 7. Save it and move to Ready

### Case A: one item, no split
1. Write the full body (existing `## Idea` + existing `## High-level design` + new `## Spec`)
   to a new temporary file made with `mktemp`.
2. Update the issue body:
   ```bash
   bash scripts/projects.sh item-update-body <itemId> <tempBodyFile>
   ```
3. Set Size and Estimate:
   ```bash
   bash scripts/projects.sh set-field <projectId> <itemId> Size "<Size>"
   bash scripts/projects.sh set-field <projectId> <itemId> Estimate "<Estimate>"
   ```
4. Move status to Ready:
   ```bash
   bash scripts/projects.sh set-status <projectId> <itemId> Ready
   ```
   It prints the status it reads back. If it isn't `Ready`, tell the user.
5. Delete the temporary file.

### Case B: split into sub-issues
1. The original item remains in its column (or tracks progress via the board's
   *Sub-issues progress* field).
2. Take two IDs from the `item <itemId>` line you read in step 4: the parent's
   `<contentId>` (7th column, the issue itself) and `<repoId>` (8th column). Every
   child goes in the parent's repository.
3. For each child slice:
   - Prepare a body file containing the parent's `## Idea` and `## High-level design`,
     followed by the child's specific `## Spec`.
   - Create the sub-issue on the repository and add it to the board:
     ```bash
     bash scripts/projects.sh create-sub-issue <projectId> <parentContentId> <repoId> "<parentTitle>: <childTitle>" <childBodyFile>
     ```
     This outputs `<childItemId>\t<childNumber>\t<childUrl>\t<childIssueId>\t<linked>`.
     The issue now exists, so never run this again for the same child: a second run
     makes a duplicate. If `<linked>` is `false`, it couldn't be attached to the
     parent. Tell the user, since `vibe-engineering:approve` uses that link to know
     when the parent is finished; they can attach it under the parent's
     *Sub-issues* on GitHub.
   - Set Size and Estimate on the child item:
     ```bash
     bash scripts/projects.sh set-field <projectId> <childItemId> Size "<ChildSize>"
     bash scripts/projects.sh set-field <projectId> <childItemId> Estimate "<ChildEstimate>"
     ```
   - Set child item status to `Ready`:
     ```bash
     bash scripts/projects.sh set-status <projectId> <childItemId> Ready
     ```
   - Clean up the child body file.

## 8. Report

Report in a few lines:
- The Ready item(s), their numbers, titles, and links
- Sizing (`Size`) and estimate (`Estimate`)
- Next step: `vibe-engineering:develop`, which will pick up a Ready item, create a
  feature branch, and write the code adhering strictly to the spec.
