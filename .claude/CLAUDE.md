# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repository is

A Claude Code **plugin** (and its own marketplace), not an application. There is
no build and no package manager. The product is Markdown instructions
(`skills/*/SKILL.md`) plus Bash helper scripts that call GitHub Projects (v2)
through the GitHub CLI, and one TypeScript hooks module, the side panel
(`hooks/panel.tsx`), which Claude Code loads as it is.

## Commands

```bash
claude plugin validate . --strict      # run before every push (release checklist)
bash tests/syntax.sh                   # syntax check of every script: bash -n on each one (bash -n with several files checks only the first)
bash scripts/projects.sh help          # prints the command reference from the header comment
claude plugin test .                   # runs the side panel's tests (tests/*.test.tsx); no GitHub needed
bash tests/next/run.sh                 # runs next.sh board against a stand-in gh and fixtures (needs jq; counts process starts on Linux, where strace can trace, and NEED_STRACE=1 makes that a must)
bash tests/repo/run.sh                 # runs repo.sh's review thread commands and pr-edit against a stand-in gh and fixtures (needs jq)
bash tests/vibe-dir/run.sh             # runs vibe-dir.sh in real git repositories it makes in a temporary folder (needs git; no jq, no GitHub)
python docs/images/src/render.py [banner] [flow] [icon]   # re-render images after editing their sources (needs Chrome/Edge + Pillow)
```

Try the plugin locally with `claude --plugin-dir .`. Scripts that touch GitHub
need `gh auth login -s project`, and they **cannot run in Claude Code cloud
sessions**: the Projects GraphQL API is blocked there (`check-auth.sh` exits 6,
`STATUS=projects_unavailable`). Test board-changing commands on a throwaway
board, never on the template.

## Architecture

- **The board is the product's memory.** Each feature is one GitHub Projects
  item that moves Draft → Backlog → Ready → In progress → In review → Done.
  Each skill owns exactly one fixed `##` section of the item body (`## Idea`,
  `## High-level design`, `## Spec`), never edits another's, and nests its own
  headings at `###`. The full flow, rules and design decisions are in
  `docs/concept.md`; read it before adding or changing a delivery skill.
- **Skills never call GitHub directly.** Every GitHub call goes through
  `scripts/projects.sh` (the board: subcommands such as `owners`, `repos`, `copy`,
  `link`, `verify`, `board`, `items`, `draft-create`, `set-status`),
  `scripts/repo.sh` (pull requests and issues: `pr`, `checks`, `pr-create`,
  `pr-edit`, `pr-comments`, `pr-threads`, `resolve-thread`, `pr-review`,
  `merge`, `issue-parent`) and `scripts/check-auth.sh`.
  `scripts/companions.sh` reports which companion plugins are installed.
  `scripts/vibe-dir.sh` makes the `.vibe` folder and keeps it out of git; it
  calls only `git`.
  Skills reach them as `bash <skill-dir>/../../scripts/<name>.sh`. Scripts that
  only one skill uses live in that skill's own `scripts/` folder.
- **Script output contract.** Scripts print machine-readable lines that the
  SKILL.md parses: `KEY=value` with documented exit codes (`check-auth.sh`,
  `update.sh`), or tab-separated rows (`projects.sh`). A `FIX=` line is shown to
  the user verbatim. If you change an output format, update every SKILL.md that
  reads it. Scripts must depend only on `gh` (no `jq`; use `gh --jq`) and stay
  LF-only (`.gitattributes`), as they run on Windows Git Bash, macOS and Linux.
  When a call fails, `gh api` prints GitHub's raw JSON on standard output and
  its own message on standard error. `repo.sh resolve-thread` and
  `repo.sh pr-edit` keep both from the caller and print one `ERROR:` line on
  standard error, built by `gh_reason`: write a new command the same way.
  They also keep away what gh writes on standard error when a call succeeds,
  such as a hint. The older commands still pass GitHub's answer
  through. Leave `repo.sh pr-review` that way, because `review` reads that
  answer when GitHub refuses a line.
  Under `pipefail`, check text a script already holds with Bash itself, and
  never end a pipe in a command that stops reading early (`grep -q`, `head`,
  `awk` with `exit`): the answer then changes from run to run.
  A new command takes text for GitHub that a person wrote, such as a title
  or a description, from a file, never as an argument: quotes, backticks
  and dollar signs then arrive as written. `repo.sh pr-edit` takes both that
  way. The older commands take only the description from a file:
  `repo.sh pr-create`, `projects.sh draft-create` and
  `projects.sh create-sub-issue` still take the title as an argument, where
  the shell changes a backtick or a dollar sign inside double quotes.
- **`create-board` copies a template project** (`gh project copy` of
  `users/gelonezi/projects/6`, overridable with
  `VIBE_ENGINEERING_TEMPLATE_OWNER` / `_NUMBER`). Boards are always created
  private. `skills/create-board/references/board-spec.md` describes the
  template and is what `verify` output is compared against, so keep it in step
  with project 6. `projects.sh build` is the from-scratch fallback.
- **Companion plugins are optional.** `promote-backlog`, `develop` and `review`
  hand part of a step to `superpowers`, `code-review` and
  `claude-md-management`; `skill-creator` is recommended too. Every hand-over is
  written as "if it's available, use it; otherwise do this yourself", and its
  output still goes where the board flow says (the item's section, the review
  checklist). Don't add them to `dependencies` in `plugin.json`: Claude Code
  then refuses to load the plugin when one is missing. `update` reports missing
  ones through `scripts/companions.sh`. Keep the list in step there, in
  `README.md` and in `docs/concept.md`.
- **The side panel is a mod.** `hooks/hooks.json` lists `hooks/panel.tsx` under
  `modules`: a pane beside the chat with a button per item's next step. A button
  only sends a prompt (`$.prompt.submit`, as the user) that names the skill, the
  item and the board; the panel itself changes nothing on the board. It reads
  the board through `scripts/next.sh` with `$.process.run`, and
  `skills/ui/SKILL.md` opens it through the tool it registers,
  `mcp__vibe-engineering__show_board`. The panel opens only from something the
  person did (their prompt, the `/vibe-board` command it registers, a press):
  Claude Code places an open from a tool call only on wide terminals. Its
  `tool.check` hook turns an `ask` for its own read-only tool into `allow`,
  and leaves a `deny` alone. Mods need Claude Code 2.1.287 or later,
  so keep it working without them: `ui` falls back to a chat guide when the
  tool is missing. Keep the empty `"hooks": {}` in `hooks.json`: older
  versions read that file as settings-style hooks and fail it without the key.
  The panel keeps its state in module variables and `$.store`, so it needs no
  `$.state` contract (`types` in `plugin.json`). The API reference is the `plugin-authoring`
  skill's `types/claude-code.d.ts`; it moves between releases, so check it
  rather than memory. Cloud sessions draw no panes and can't reach boards, so
  try the panel on your own computer with `claude --plugin-dir .`.
- **`scripts/next.sh` decides the next step.** It is the one place that maps a
  column to the skill that moves an item out of it. The panel and the chat
  guide both read it. When the flow changes, change it with `docs/concept.md`.
  The panel runs it on every refresh, so keep `board` to its three GitHub
  calls and start no process per item (no `$(...)` inside its loops: helpers
  set a variable instead), and update `tests/next/` when a step's rule
  changes. The rule for Fix comments is written in three places that must
  agree: the script's header, `docs/concept.md` and `README.md`.
- **Review threads are read from one end.** `next.sh board`,
  `repo.sh pr-threads` and `repo.sh pr-comments` all read the newest 100
  threads of a pull request (`reviewThreads(last: 100)`), so the threads that
  keep Fix comments on are the ones `push` can resolve. Change them together;
  `tests/repo/run.sh` fails when one differs. `develop` hands the threads it
  fixed to `push` in `.vibe/fixed-threads-<prNumber>.txt`, and `push`
  resolves them only after the fix is pushed. The file is kept out of git
  as the checklist of `review` is, through git's exclude file. Both skills
  call `scripts/vibe-dir.sh` for that, and write no shell lines of their
  own: `push` stops when `git status` shows the hand-over file. The script
  asks git whether `.vibe/` is ignored (`git check-ignore --no-index`) and
  adds the pattern only when it is not, on a line of its own, also when the
  file's last line has no line break. Keep `--no-index`: without it, one
  committed file under `.vibe/` makes git answer "not ignored" although a
  new file there is ignored, and the script then fails on every run. It
  takes the file's path from
  `git rev-parse --git-path info/exclude`, never a fixed `.git/info/exclude`:
  in a git worktree or a submodule `.git` is a file.
- **`push` keeps an open pull request's text true.** On a push to a pull
  request that was already open, `push` checks the title and description
  against the branch and asks before it changes them with `repo.sh pr-edit`.
  `approve` builds the squash commit's subject from that title. `pr-edit`
  refuses a description that drops a `Closes <repo>#<number>` line the pull
  request has: that line links it to its issue, and the panel finds a pull
  request by it when the branch name does not match.
- **GitHub runs the script checks.** `.github/workflows/checks.yml` runs
  `tests/syntax.sh`, `tests/next/run.sh`, `tests/repo/run.sh` and
  `tests/vibe-dir/run.sh` on Linux,
  macOS and Windows (in Git Bash), for every pull request and every push to
  `main`. They need no Claude Code and no GitHub login, so the workflow has
  no secrets and can only read the repository. It does not run
  `claude plugin validate` or `claude plugin test`: those still run by hand.
  Each check ends in a `PASS:` line, which a job's log shows. Add a new
  script test as one more step there, and keep it runnable by hand with the
  same command. When a job fails on one system, fix the script or the test:
  never take the system out of the list. The tests of `next.sh` and
  `repo.sh` need a `jq` binary
  and say so when it is missing; the plugin's own scripts still must not
  need one. The test of `vibe-dir.sh` needs only git. A jq built for Windows ends each line with a carriage return,
  so there the tests run it in binary mode (`-b`), which needs jq 1.7 or
  newer. Never pass `-b` to every jq: jq 1.6, which older Linux systems
  still ship, stops at it, and the tests must keep passing with it. Only the
  Linux job counts process starts: macOS has no `strace`, and the one in Git
  Bash can't make this count. The macOS job runs Bash 3.2, so keep the
  scripts and the tests to what that version can run. One thing it can't
  run, and `bash -n` does not catch: a `case` inside `$(...)`. Put the
  `case` in a function, or on lines of its own.
- **Mutations are not idempotent.** `copy`, `draft-create`, `convert-draft`,
  `create-sub-issue` and `pr-create` create a new
  object each run; skills must never retry them, only follow-up steps such as
  `link` or `set-status`. `repo.sh resolve-thread` is safe to run again:
  resolving a thread that is already resolved changes nothing (checked on a
  real thread). `repo.sh pr-edit` is safe to run again too: setting the
  title and description a pull request already has changes nothing, not even
  its time of last update (checked on a real pull request). It still changes
  what everyone sees, so `push` asks first. `scripts/vibe-dir.sh` adds
  nothing on a second run. Status is set last and read back, because board
  automations may move items.

## Conventions for skills

- Skills are invoked as `vibe-engineering:<name>`; the frontmatter
  `description` is what triggers them, so list the user's likely phrasings.
- Never guess IDs, logins or project numbers: take them from script output.
  Ask the user which board to use; never pick one.
- Ask before anything that can't be undone (merging, posting, deleting).
- **Plain words first:** a skill explains itself in language a person without
  an engineering background can follow. Docs and skills are written in plain,
  short sentences without em dashes.
- All eight delivery skills exist, plus `ui`, `help` and `update`. The skills after
  `create-item` find an item's pull request by its branch name,
  `feature/<issueNumber>-<slug>`, which `develop` creates: keep that pattern.
- Check a changed skill with Skill Creator's validator, from the skill-creator
  plugin's folder: `python3 -m scripts.quick_validate <path-to-skill>`.

## Releasing a change

1. Bump `version` in `.claude-plugin/plugin.json` **and** the version badge in
   `README.md`. Without a bump, `vibe-engineering:update` won't fetch the change.
   An item's spec names "the next patch version after main", never a fixed
   number: other items may merge first. Take the number when the item is
   developed, and take it again if `main` got a release before the merge.
2. Keep `README.md`, `docs/concept.md`, `docs/roadmap.md` and the hand-written
   `skills/help/assets/help.html` consistent with which skills exist.
3. `description`/`displayName` appear in both `plugin.json` and
   `marketplace.json`; the marketplace entry wins, so change both together.
4. Run the script checks: `bash tests/syntax.sh`, `bash tests/next/run.sh`,
   `bash tests/repo/run.sh` and `bash tests/vibe-dir/run.sh`. GitHub runs the
   same four on Linux, macOS and Windows for the pull request, and its checks
   must pass before the merge.
5. Run `claude plugin validate . --strict` and, when the panel changed,
   `claude plugin test .`. These two run only by hand: GitHub does not run
   them.

Commit messages follow the existing style: a short imperative summary, with
`, release X.Y.Z` appended when the version is bumped.
