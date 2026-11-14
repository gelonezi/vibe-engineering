---
name: create-item
description: Refine a new feature idea through conversation, using the software's own context, and save it as a Draft item on the GitHub Projects board. Use when the user has a new idea, feature request, problem or bug to record, says something like "I think we should...", or wants to add, create or draft an item, card or ticket on their board. Scope is the concept only, not its design or implementation.
---

# vibe-engineering:create-item

Helps the user turn a new idea into a Draft item on their board. The item is
where every later skill starts, and the flow is described in
[docs/concept.md](../../docs/concept.md).

Every GitHub call goes through two scripts in the plugin's `scripts/` folder.
Run them with `bash <skill-dir>/../../scripts/<name>.sh`; the steps below
shorten that to `bash scripts/<name>.sh`. Never guess IDs: get each one from a
script's output.

## 1. Check GitHub access

Run `bash scripts/check-auth.sh` and read its `KEY=value` lines.

- `STATUS=ok`: continue.
- `STATUS=projects_unavailable`: this session can't reach GitHub Projects at
  all, which is the case in Claude Code cloud sessions, and a different token
  wouldn't change it. Don't show the `FIX` line as a command and don't suggest
  a token. Tell the user in one or two sentences, and ask them to run this
  skill from Claude Code on their own computer. Don't try another route, such
  as GitHub's REST API or an MCP server. Then stop.
- Any other status: stop. Show the user the `FIX` line as a command they can
  run, explain it in one sentence, and offer to run the check again once
  they've done it. Don't try to work around it.
- Pass any `WARN` lines on in one sentence each, and continue.

## 2. Find the board

The user must tell you which board to use: its link, or its board, panel or
project name. If they haven't, ask and wait. Never choose one yourself, whether
from the current repository, an earlier run or the only board you can find.

Run `bash scripts/projects.sh board "<what they told you>"`. It prints one line
per match: `<number>  <id>  <title>  <url>`.

- **One match:** use it, and name it in your report.
- **Several matches:** the same name exists under different owners. Show their
  URLs and ask which one.
- **No match, or an error:** tell the user, and ask them to check the name or
  send the link. If they want to see their boards, run
  `bash scripts/projects.sh list <ownerLogin>`. If they have none, offer
  `vibe-engineering:create-board`.

Keep the project's ID and URL for the next steps.

## 3. Shape the idea

An idea is the concept of a new feature, in the user's own terms. It starts from
something they say, such as:

> I think we should implement galpon names with the stock, so I can say I have
> 40kg of iron in Stock 01 and 20kg of iron in Stock 02.

Refine it by talking with them, for as many rounds as it takes. There is no
checklist to fill in and no limit on questions.

**Learn the software first.** Before your first question, read what you need to
understand the part of the software the idea touches: the current repository's
docs and code, read-only. If you aren't in the right repository, ask where the
software is. If it isn't available, say so and continue from the conversation.

**Ask questions only the software could raise.** Compare the idea with how things
work today, and ask about the gaps you find. In the example, if the software
keeps one stock total per material, ask what should happen to the totals that
already exist. Ask one question at a time, and tell the user what you found when
it explains why you're asking.

**Stay on the concept.** Talk about what the user wants to be able to do, and
why. Don't propose a design, tasks or an implementation: those belong to
`vibe-engineering:promote-backlog` and `vibe-engineering:promote-ready`. If the
user brings solution details, keep them as notes.

**Let the user decide when it's finished.** Keep going until they say it's right,
or you have nothing left to ask and they agree. If they don't know an answer, list
it as an open question instead of inventing one.

Write the item in the language the user is using. The body starts with an
`## Idea` heading, and any headings inside it start at `###`. It holds their
original words, then the concept as refined, including what you settled together:

```markdown
## Idea

> I think we should implement galpon names with the stock, so I can say I have
> 40kg of iron in Stock 01 and 20kg of iron in Stock 02.

(The concept as refined: what the user will be able to do, and the decisions
made while talking it through.)

### Open questions

(Only if some remain.)
```

## 4. Confirm

Show the proposed title and body, and change them until the user agrees. Don't
create the item before they do.

## 5. Create the item

1. Write the body to a new temporary file.
2. Create the draft issue:
   `bash scripts/projects.sh draft-create <projectId> "<title>" <bodyFile>`.
   It prints the item's ID.
3. Put it in the Draft column:
   `bash scripts/projects.sh set-status <projectId> <itemId> Draft`.
   It prints the status it reads back.
4. Delete the temporary file.

If step 2 fails, nothing was created, so tell the user why. If step 3 fails, the
item already exists without the right status. Tell the user, and retry only
`set-status`. Never run `draft-create` again, because that makes a duplicate.

Board automations can also move new items, and may run a moment later. Check
with `bash scripts/projects.sh item-status <itemId>`, and if it isn't `Draft`,
tell the user which status it has.

## 6. Report

Report in a few lines:

- the item's title, and the board's URL as a link
- its status
- the next step: `vibe-engineering:promote-backlog`, when the idea is ready for a
  high-level design

Draft issues have no number, so the user finds this item by its title.
