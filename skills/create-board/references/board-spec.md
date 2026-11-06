# Board spec: "Iterative development"

The board `vibe-engineering:create-board` produces. It follows GitHub's built-in
**Iterative development** template, as set up in the reference project
(Planner, `https://github.com/orgs/se-oriente-solucoes/projects/1`).

The normal path **copies the public template project**, so everything below
comes across exactly as the template has it. This file is only needed for the
fallback build (template unreachable), and as the checklist for what to verify.

## Status field (board columns)

| Option      | Color  | Description                       | Column limit |
|-------------|--------|-----------------------------------|--------------|
| Draft       | Gray   | This idea is still growing        | none         |
| Backlog     | Green  | This item hasn't been started     | 3            |
| Ready       | Blue   | This is ready to be picked up     | none         |
| In progress | Yellow | This is actively being worked on  | 3            |
| In review   | Purple | This item is in review            | 5            |
| Done        | Orange | This has been completed           | none         |

Column limits are a view setting (board column menu → *Set limit*).

## Custom fields

| Field      | Type          | Values                         |
|------------|---------------|--------------------------------|
| Priority   | Single select | P0, P1, P2                     |
| Size       | Single select | XS, S, M, L, XL                |
| Estimate   | Number        | Summed in each column header   |
| Iteration  | Iteration     | 2-week iterations              |

The fallback build's Priority/Size colors and iteration length are best
guesses. The template copy is the source of truth.

## Views

| # | View                | Layout  | Filter                | Notes                                   |
|---|---------------------|---------|-----------------------|-----------------------------------------|
| 1 | Current iteration   | Board   | `iteration:@current`  | Columns by Status, sum of Estimate      |
| 2 | Next iteration      | Board   | `iteration:@next`     | Columns by Status                       |
| 3 | Prioritized backlog | Board   | (none)                | Sort by Priority                        |
| 4 | Roadmap             | Roadmap | (none)                | Dates from Iteration                    |
| 5 | In review           | Table   | `status:"In review"`  |                                         |
| 6 | My items            | Table   | `assignee:@me`        |                                         |

## Creating views by hand (fallback only)

`projects.sh build` does not create views. For each row in the table above:

1. Open the project, click **+ New view**, and pick the layout.
2. Double-click the tab to rename it.
3. Type the filter into the filter bar.
4. On board views, open **View** → *Column by* → **Status**, and *Field sum* → **Estimate**.
5. Click **Save** next to the filter bar.

Then rename the default "View 1", or delete it.
