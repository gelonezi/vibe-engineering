---
name: ui
description: Show the vibe-engineering board beside the chat, with a button for each item's next step, or list the board and its next steps in the chat when the side panel isn't available. Use when the user asks to open the UI, the panel, the dashboard or the board view, asks what's next, where things stand, which item to work on, what is waiting for them, or wants help choosing the right vibe-engineering skill.
---

# vibe-engineering:ui

Shows the board and what comes next for each item, so the user doesn't have
to remember which skill moves which column. The flow is described in
[docs/concept.md](../../docs/concept.md).

There are two ways to show it, and the user gets the same steps from both:

- **The side panel.** A pane beside the chat that lists the items by column,
  each with a button for its next step. A button sends an ordinary prompt that
  names the skill, the item and the board. It's drawn by Claude Code 2.1.287
  and later, on the user's own computer, and the panel's tool,
  `mcp__vibe-engineering__show_board`, exists only there. The panel also adds
  the `/vibe-board` command, which opens it on the board it showed last, at
  any terminal width.
- **The chat guide.** The same board and steps as text, then a short list to
  pick the next step from. Used whenever the panel can't be shown.

This skill only reads the board. Every change is made by the skill the user
picks, with that skill's own checks and questions.

Every GitHub call goes through the scripts in the plugin's `scripts/` folder.
Run them with `bash <skill-dir>/../../scripts/<name>.sh`; the steps below
shorten that to `bash scripts/<name>.sh`. Never guess IDs: get each one from a
script's output.

## 1. Check GitHub access

Run `bash scripts/check-auth.sh` and read its `KEY=value` lines.

- `STATUS=ok`: continue.
- Any other status: stop. Show the user the `FIX` line as a command they can
  run, explain it in one sentence, and offer to run the check again once
  they've done it. Don't try to work around it.
- Pass any `WARN` lines on in one sentence each, and continue.

## 2. Find the board

If the user named a board (its link, or its board, panel or project name), run
`bash scripts/projects.sh board "<what they told you>"`. It prints one line
per match: `<number>\t<id>\t<title>\t<public>\t<url>`.

- **One match:** use it.
- **Several matches:** show their URLs and ask which one.
- **No match, or an error:** tell the user, and ask them to check the name or
  send the link.

If the user didn't name one:

- **The panel's tool is available:** call it with no arguments. The panel
  remembers the board it showed last in this folder. If the result starts
  with `NO_BOARD`, ask the user which board to show and wait. Otherwise say in
  one line which board it shows, and that they can press **Change board** or
  name another one.
- **The tool isn't available:** ask the user which board to show, and wait.
  Never choose one yourself, from the current repository, an earlier run or
  the only board you can find.

If the user has no board yet, offer `vibe-engineering:create-board` and stop.

## 3. Open the side panel

If the tool `mcp__vibe-engineering__show_board` is available, call it with the
board's `projectId`, `title` and `url` from step 2. Its result is plain text:

- `PANEL=shown`: the panel is open. Tell the user in one or two lines: which
  board it shows, and the most useful next step (step 5 says which). Then
  stop: the buttons do the rest. Don't list the board in the chat as well.
- `PANEL=not_shown`: the panel couldn't be opened from here, often because
  the terminal is narrow. Continue with the chat guide, using the items the
  result lists, and tell the user in one line that typing `/vibe-board` opens
  the panel at any width.
- `ERROR=<text>`: the board couldn't be read. Pass the text on, in one
  sentence, and stop.

If the tool isn't available, don't mention it: continue with the chat guide.
At most, say once that a newer Claude Code on their own computer shows this as
a panel beside the chat.

## 4. The chat guide

Run `bash scripts/next.sh board <projectId>`. It prints one line per item:

`<itemId>\t<status>\t<type>\t<number>\t<repo>\t<subDone>/<subTotal>\t<steps>\t<title>`

`<steps>` is a comma-separated list of `<skill>:<label>`, or `-` when nothing
is started from here: a Done item, an item with no status, a pull request on
the board, or a parent whose sub-issues carry the work. The script is the one
place that decides the next step, so take the steps from it and don't work
them out yourself.

Show the board by column, the column to act on first at the top, as the
panel does: In review, In progress, Ready, Backlog, Draft, then items with no
status, then Done. For each item give its number
(or "draft"), its title and its step labels. For a parent, give its progress,
such as "2 of 5 sub-issues done", instead. For Done, give the count only.
Leave out empty columns.

Then offer the next steps as a pick list, with the AskUserQuestion tool if you
have it: up to four options, most advanced first (In review, In progress,
Ready, Backlog, Draft), plus **New idea** when there's room. Each option's
label is the step and the item, such as "Write the spec: Low-stock alerts".

## 5. Start the step

When the user picks a step, here or by typing, start that skill on that item
and that board, as if they had asked for it:

| Step | Skill | What to ask it for |
| --- | --- | --- |
| Design it | `vibe-engineering:promote-backlog` | The item |
| Write the spec | `vibe-engineering:promote-ready` | The item |
| Build it | `vibe-engineering:develop` | The item |
| Open the pull request | `vibe-engineering:push` | The item |
| Update the pull request | `vibe-engineering:push` | The item |
| Review | `vibe-engineering:review` | The item |
| Fix comments | `vibe-engineering:develop` | The review comments on the item |
| Merge | `vibe-engineering:approve` | The item |
| New idea | `vibe-engineering:create-item` | The board |

Name the board by its URL and the item by its title and `<repo>#<number>`,
or as a draft item by its title. The side panel's buttons send these same
words.

When you only need to suggest one step, such as after opening the panel,
prefer the item closest to Done: something In review waits for the user, and
merging it finishes work already paid for.
