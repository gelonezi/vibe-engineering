# Concept: the vibe-engineering skill set

The skills move one piece of work across a GitHub Projects board, from a rough
idea to merged code. Everything a later skill needs is saved in the item itself.

## The flow

| Skill             | Picks up                         | Ends in     | Writes                                        |
|-------------------|----------------------------------|-------------|-----------------------------------------------|
| `create-board`    | –                                | –           | The board                                     |
| `create-item`     | A new idea                       | Draft       | `## Idea`                                     |
| `promote-backlog` | Draft item, or picks from a list | Backlog     | `## High-level design`                        |
| `promote-ready`   | Backlog item with an HLD         | Ready       | `## Spec`, Size, Estimate                     |
| `develop`         | Ready item                       | In progress | Code on a branch, Iteration                   |
| `push`            | In progress item                 | In review   | Branch, PR with description, link to the item |
| `review`          | In review item or PR link        | In review   | The inline comments the user selected         |
| `approve`         | In review item                   | Done        | The merge                                     |

### Fixing review comments

`develop` also accepts an In review item with open review comments, and moves
it back to In progress. `push` then updates the same PR and returns the item to
In review.

## Rules

- **One Ready item equals one PR.** `promote-ready` splits work until this is true.
- **The item is the only context.** `develop` reads the item and the destination
  repository's own rules, and nothing else.
- **Each skill owns one section.** It writes its own section and never edits the
  others. Sections use fixed `##` headings, in this order: `## Idea`,
  `## High-level design`, `## Spec`. Headings inside a section start at `###`,
  so a section always ends at the next `##`.
- **Column and content must agree.** A skill that finds an item in the wrong
  column, or missing an earlier section, says so and asks before continuing.
- **Set the status last, then check it.** Board automations can move items too,
  so a skill reads the status back and reports any difference.
- **Warn near the size limit.** GitHub issue bodies stop at about 65,000
  characters, and text accumulates in one item, so `promote-ready` warns before
  reaching it.

## Decisions

### An idea is refined by conversation

An idea is the concept of a new feature, in the user's own terms. `create-item`
has no checklist and no limit on questions. It reads the software, asks about the
gaps between the idea and how things work today, and continues until the user
says it's right. The `## Idea` section keeps their original words, followed by the
refined concept, the decisions made along the way, and any open questions.

### A Draft item is a GitHub draft issue

`create-item` creates a draft issue, because an idea doesn't need a repository
yet. `promote-backlog` turns it into a real issue once the repository is known,
because only real issues can link to PRs. Draft issues have no number, so they
are picked from a list.

The Draft column and GitHub's draft issues are separate things. An item in the
Draft column can be a real issue, and a draft issue can sit in any column.

### Splitting an item

- **One result:** the same item moves on, and the new text goes below the old text.
- **Several results:** the original stays in its column as the parent, and each
  child is a sub-issue with its own copy of the text above it.
- **Finishing:** the parent shows progress through the board's *Sub-issues
  progress* field, and `approve` closes it when the last child is done.

The copies can go out of date if the parent changes later. That's the price of
letting `develop` work from a single item. Parents also count against column
limits, which GitHub only displays and doesn't enforce, so skills don't block on
them.

### Review comments are selected in a checklist file

`review` writes a Markdown file kept out of commits, with one `- [ ]` per
comment showing the file, line and proposed text. The user ticks what to post,
edits the wording if needed, and asks to post. The rest are discarded.

### The user always names the board

The user must tell each skill which board to use: its link, or its board, panel
or project name. A skill asks if it wasn't told, and never chooses one itself,
whether from the current repository, an earlier run or the only board it can
find. There is no config file.

## GitHub limits to design around

- **You can't approve your own PR.** GitHub blocks both approving and requesting
  changes on your own PR. `review` posts plain comments, and when working solo
  `approve` merges without a formal approval. If branch protection requires an
  approval, the skill stops and tells the user. It never works around it.
- **Merging can't be undone.** `approve` shows the checks and any unresolved
  threads, and asks for confirmation before merging.
- **Items need an Iteration to show up.** The Current iteration and Next
  iteration views filter on it, so `develop` sets it.
- **Automations compete with skills.** The API shows each automation's name and
  whether it's on, but not which column it moves items to.

## Status

Built: `create-board`, `create-item`. The other six skills are not built yet.
