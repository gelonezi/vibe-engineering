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
| `develop`         | Ready item                       | In progress | Code on a branch                              |
| `push`            | In progress item                 | In review   | Branch, PR with description, link to the item |
| `review`          | In review item or PR link        | In review   | The inline comments the user selected         |
| `approve`         | In review item                   | Done        | The merge                                     |

The next step for each column is decided in one place, `scripts/next.sh`.
`ui` shows it beside the chat or in the chat, and starts the skill the user
picks (see [The side panel](#the-side-panel-guides-only)).

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
are picked from a list. A draft issue is only visible to people who can see the
board, so if the board is public, `create-item` says so and asks before saving.

In a cloud session `create-item` can't reach the board, so it offers two ways
forward: continue in Claude Code on the user's computer, or shape the idea in
the session and add it to the Draft column by hand, guided step by step.

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

### The board is a copy of a public template

`create-board` copies
[project 6 in the `gelonezi` account](https://github.com/users/gelonezi/projects/6).
On the user's computer the skill asks two things from lists it builds: the
owner (their account or one of their organizations), and whether the board is
for the whole account or linked to one repository. Then it makes the copy.
The board is always created private, and the user can make it public later in
its settings.

In a cloud session it can't, so it offers two ways forward: continue in Claude
Code on the user's computer and call the skill again there, or make the copy
by hand with GitHub's *Make a copy*, guided step by step. The skill can't check
a board made that way, so it gives the user a short checklist.

### Companion plugins do what they already do well

The plugin works best with four others from the official marketplace:
`superpowers`, `code-review`, `claude-md-management` and `skill-creator`. A
skill hands the first three a part of its step and keeps everything about the
board for itself:

- `promote-backlog` uses `superpowers:brainstorming` to choose the approach with
  the user. The result goes in `## High-level design`, not in a file, and the
  skill stops before `superpowers:writing-plans`, because the spec belongs to
  `promote-ready`.
- `develop` uses `superpowers:test-driven-development`,
  `superpowers:systematic-debugging`,
  `superpowers:verification-before-completion` and, for review fixes,
  `superpowers:receiving-code-review`. Before committing it offers
  `claude-md-management:revise-claude-md`, so what was learned ships in the same PR.
- `review` runs `code-review:code-review` without `--comment`, adds its findings
  to the checklist, and checks the PR against the spec itself.

`create-item` and `promote-ready` hand nothing over. Brainstorming moves on to a
design, which an idea must not have yet, and a written plan is far longer than an
issue body allows.

The companions are optional. Every hand-over says what to do when the companion
isn't there, so a missing plugin makes a step less thorough but never stops it.
`update` checks which ones are installed, with `scripts/companions.sh`, and
gives the command that installs each missing one.

Claude Code can install them automatically, through `dependencies` in
`plugin.json`. That was tried and dropped, because a declared dependency is
strict: Claude Code refuses to load this plugin while one is missing or turned
off, which happens when the official marketplace isn't added or the plugin is
turned on from claude.ai.

No delivery skill uses `skill-creator` yet. It's recommended so that the user has
it for their project's own skills, which the Set up track in
[roadmap.md](roadmap.md) builds on.

### No iterations

The board has no Iteration field. Work is pulled from Ready one item at a time,
and the Roadmap view uses Start date and Target date. This removes a trap of
iteration boards, where an item without an iteration doesn't show up.

### The user always names the board

The user must tell each skill which board to use: its link, or its board, panel
or project name. A skill asks if it wasn't told, and never chooses one itself,
whether from the current repository, an earlier run or the only board it can
find. There is no config file.

The side panel is the one exception. It remembers the board the user named
last in that folder, shows its name at the top with a **Change board** button,
and still names the board in every prompt it sends, so the skill that runs is
always told which board to use.

### The side panel guides, only

Some people find it hard to run a process through skill names alone. `ui` shows
the board beside the chat, in a pane that Claude Code draws for the plugin, with
a button for each item's next step:

| Column | Button | Skill |
| --- | --- | --- |
| Any time | New idea | `create-item` |
| Draft | Design it | `promote-backlog` |
| Backlog | Write the spec | `promote-ready` |
| Ready | Build it | `develop` |
| In progress | Open the pull request, or Update the pull request once it's open | `push` |
| In review | Review, Fix comments, Merge | `review`, `develop`, `approve` |
| A parent with sub-issues | None: it shows its progress | |

The panel finds an item's pull request as the other skills do, by its branch
`feature/<issueNumber>-<slug>`, and else by the `Closes` line `push` writes.
Fix comments follows the state the pull request shows on GitHub:

- **A reviewer requested changes.** The button stays until that reviewer
  reviews again, as GitHub's own merge box does.
- **A review thread is unresolved.** After fixing review comments, `develop`
  lists the threads it fixed and, if the user agrees, marks them resolved. A
  thread it only answered stays open for the reviewer.
- **Someone else wrote a review with only text, or a plain comment, after the
  latest commit.** These can't be resolved, so the next commit counts as the
  answer. The pull request's author's own comments and bots' comments don't
  count: in a solo project the author is also the reviewer, and their
  feedback arrives as review threads.

If the panel can't find the pull request, it offers Fix comments anyway,
because it can't tell. The panel reads all of this in at most three calls to
GitHub, however many items are in review.

A button sends an ordinary prompt, as the user's own words, that names the
skill, the item and the board. The skill then runs as if the user had typed it,
with its own checks and questions, and `approve` still asks before it merges.
The panel never moves an item itself, and items can't be dragged between
columns, because only a skill may move an item, after writing its section.
Buttons wait while Claude is working, including while a skill's background
agents finish, and the panel reads the board again when Claude is done.

The columns are listed with the one to act on first at the top: In review, In
progress, Ready, Backlog, Draft, then Done as a count. A pane can be short, so
what needs the user most is what they see first, and the panel says when more
is below. The panel opens when the user asks for it, through `ui` or the
`/vibe-board` command, which opens it at any terminal width. Its own tool only
reads the board, so it runs without a permission prompt; a rule that denies it
still stands.

The panel is a Claude Code mod, which needs Claude Code 2.1.287 or later on the
user's computer. It needs no Node, no server and no browser. Where it can't be
drawn (an older Claude Code, a cloud session, an organization that turned mods
off), `ui` shows the same board and steps in the chat and offers them as a
pick list. A web page was considered and dropped: a browser has no dependable
way to hand a click back to the chat, and it would add Node and a server to a
plugin that otherwise needs only `gh`.

## GitHub limits to design around

- **You can't approve your own PR.** GitHub blocks both approving and requesting
  changes on your own PR. `review` posts plain comments, and when working solo
  `approve` merges without a formal approval. If branch protection requires an
  approval, the skill stops and tells the user. It never works around it.
- **Merging can't be undone.** `approve` shows the checks and any unresolved
  threads, and asks for confirmation before merging.
- **Cloud sessions can't reach boards.** In a Claude Code cloud session,
  GitHub's Projects API is blocked and the session's GitHub access covers
  single repositories only. A skill detects this in its access check and
  says so, instead of suggesting a token fix that can't work.
- **A board's default repository has no API.** `create-board` links the board
  to the repository, so it shows on the repository's Projects tab, and tells
  the user to pick the default repository in the board's settings. That
  setting decides where new issues created from the board go.
- **Automations compete with skills.** The API shows each automation's name and
  whether it's on, but not which column it moves items to.

## Status

Built: all delivery skills (`create-board`, `create-item`, `promote-backlog`,
`promote-ready`, `develop`, `push`, `review`, `approve`), plus three utilities
outside the flow: `ui`, which shows the board and each item's next step beside
the chat, `help`, which shows an illustrated page of this document, and
`update`, which updates the installed plugin.

This document covers the delivery flow only. What comes after it, such as
assessing a repository, setting a project up for agents and starting new
repositories from templates, is in [roadmap.md](roadmap.md).
