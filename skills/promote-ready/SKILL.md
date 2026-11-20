---
name: promote-ready
description: Specify, size, and move a Backlog item to Ready on your GitHub Projects board, splitting it into sub-issues if needed so that one Ready item equals one pull request. Use when an item with an idea and high-level design is ready to be specified and picked up for development.
---

# vibe-engineering:promote-ready

Helps the user take an item from **Backlog** to **Ready** by writing its concrete
specification (`## Spec`), setting its `Size` and `Estimate`, and enforcing the core
rule: **One Ready item equals one pull request**. The flow is described in
[docs/concept.md](../../docs/concept.md).

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
project name. If they haven't, ask and wait. Never choose one yourself, whether
from the current repository, an earlier run or the only board you can find.

Run `bash scripts/projects.sh board "<what they told you>"`. It prints one line
per match: `<number>\t<id>\t<title>\t<url>`.

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

## 5. Shape the Spec, Size, and Sizing / Splitting

A specification tells `vibe-engineering:develop` exactly what to build and how to
verify it. It leaves no ambiguity about files, interfaces, acceptance criteria, or tests.

### 5.1. The "One Ready item = One PR" Rule
Evaluate the scope against the single pull request standard:
- Can this feature be built, tested, and reviewed safely in a single PR (ideally < 400 lines of diff)?
- If yes: keep it as a single item.
- If no (the work spans independent layers, migrations, or large sub-features): **split it into sub-issues**.

### 5.2. Sizing and Estimates
- **Size**: Assign one of `XS`, `S`, `M`, `L`, `XL`.
  - `XS`: Tiny tweak, config change, typo, 1-2 lines.
  - `S`: Small bugfix or localized component update (~under 100 lines).
  - `M`: Standard feature slice or endpoint with tests (~100-300 lines).
  - `L`: Significant feature requiring careful review (~300-500 lines).
  - `XL`: Almost certainly needs splitting. If keeping as XL, explain why.
- **Estimate**: A numeric story point or hour estimate (e.g., `1`, `2`, `3`, `5`, `8`).

### 5.3. GitHub Character Limit Check
GitHub issue bodies have a limit of ~65,000 characters. Check the character count of
the existing body plus proposed spec. If the total exceeds 50,000 characters, warn the
user and recommend splitting the item into sub-issues to avoid truncation.

### 5.4. Spec Content Structure
The spec section begins with `## Spec`. All internal headings MUST start at `###`.
Never alter the existing `## Idea` or `## High-level design` sections.

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

## 7. Apply & Move to Ready

### Case A: Single Item (No splitting)
1. Write the full body (existing `## Idea` + existing `## High-level design` + new `## Spec`)
   to a temporary file.
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
5. Remove the temporary file.
6. Verify status readback:
   `bash scripts/projects.sh item-status <itemId>`.

### Case B: Multi-item Split (Sub-issues)
1. The original item remains in its column (or tracks progress via the board's
   *Sub-issues progress* field).
2. For each child slice:
   - Prepare a body file containing the parent's `## Idea` and `## High-level design`,
     followed by the child's specific `## Spec`.
   - Create the sub-issue on the repository and add it to the board:
     ```bash
     bash scripts/projects.sh create-sub-issue <projectId> <parentContentId> <repoId> "<parentTitle>: <childTitle>" <childBodyFile>
     ```
     This outputs `<childItemId>\t<childNumber>\t<childUrl>\t<childIssueId>`.
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
