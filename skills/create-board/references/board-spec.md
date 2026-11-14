# Board spec: "Vibe Engineering - Default"

The board `vibe-engineering:create-board` produces. The normal path **copies
the public template project**, `https://github.com/users/gelonezi/projects/6`,
so everything below comes across exactly as that project has it. This file is
the checklist for what to verify, and the recipe for the fallback build when
the template can't be reached.

## Status field (board columns)

| Option      | Color  | Description                       |
|-------------|--------|-----------------------------------|
| Draft       | Gray   | This idea is still growing        |
| Backlog     | Green  | This item hasn't been started     |
| Ready       | Blue   | This is ready to be picked up     |
| In progress | Yellow | This is actively being worked on  |
| In review   | Purple | This item is in review            |
| Done        | Orange | This has been completed           |

The order matters: it is the order of the flow. Column limits are a view
setting (board column menu → *Set limit*), and they come with the copy.

## Custom fields

| Field       | Type          | Values                        |
|-------------|---------------|-------------------------------|
| Priority    | Single select | P0, P1, P2                    |
| Size        | Single select | XS, S, M, L, XL               |
| Estimate    | Number        | Summed in each column header  |
| Start date  | Date          | Used by the Roadmap view      |
| Target date | Date          | Used by the Roadmap view      |

There is no Iteration field. The flow doesn't use iterations.

## Views

| # | View           | Layout  | Filter         | Set up                                         |
|---|----------------|---------|----------------|------------------------------------------------|
| 1 | Backlog        | Board   | (none)         | Columns by Status, sorted by Priority          |
| 2 | Priority board | Board   | (none)         | Columns by Status, grouped in rows by Priority |
| 3 | Team items     | Table   | (none)         | Grouped by Status                              |
| 4 | Roadmap        | Roadmap | (none)         |                                                |
| 5 | My items       | Table   | `assignee:@me` |                                                |

## Workflows

These come with the copy, all turned on:

- Item added to project
- Item closed
- Pull request linked to issue
- Pull request merged
- Auto-close issue
- Auto-add sub-issues to project

Workflows can move items between columns on their own, which is why every
skill reads an item's Status back after setting it.

## Creating views by hand (fallback only)

`projects.sh build` creates the project and its fields, but not the views or
the workflows. For each row in the views table:

1. Open the project, click **+ New view**, and pick the layout.
2. Double-click the tab to rename it.
3. Type the filter, if any, into the filter bar.
4. Open **View** and apply the *Set up* column: *Column by* → **Status** on
   the two boards, with *Sort by* → **Priority** on Backlog and *Group by* →
   **Priority** on the Priority board; *Group by* → **Status** on Team items.
5. On board views, also set *Field sum* → **Estimate**.
6. Click **Save** next to the filter bar.

Then rename the default "View 1", or delete it. Turn the workflows on under
**⋯** → **Workflows**.

The fallback's field colors are best guesses. The template copy is the source
of truth.
