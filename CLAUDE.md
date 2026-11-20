# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repository is

A Claude Code **plugin** (and its own marketplace), not an application. There is
no build, no package manager and no test suite. The product is Markdown
instructions (`skills/*/SKILL.md`) plus Bash helper scripts that call GitHub
Projects (v2) through the GitHub CLI.

## Commands

```bash
claude plugin validate . --strict      # run before every push (release checklist)
bash -n scripts/*.sh skills/*/scripts/*.sh   # syntax check the scripts
bash scripts/projects.sh help          # prints the command reference from the header comment
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
  `pr-review`, `merge`, `issue-parent`) and `scripts/check-auth.sh`.
  Skills reach them as `bash <skill-dir>/../../scripts/<name>.sh`. Scripts that
  only one skill uses live in that skill's own `scripts/` folder.
- **Script output contract.** Scripts print machine-readable lines that the
  SKILL.md parses: `KEY=value` with documented exit codes (`check-auth.sh`,
  `update.sh`), or tab-separated rows (`projects.sh`). A `FIX=` line is shown to
  the user verbatim. If you change an output format, update every SKILL.md that
  reads it. Scripts must depend only on `gh` (no `jq`; use `gh --jq`) and stay
  LF-only (`.gitattributes`), as they run on Windows Git Bash, macOS and Linux.
- **`create-board` copies a template project** (`gh project copy` of
  `users/gelonezi/projects/6`, overridable with
  `VIBE_ENGINEERING_TEMPLATE_OWNER` / `_NUMBER`). Boards are always created
  private. `skills/create-board/references/board-spec.md` describes the
  template and is what `verify` output is compared against, so keep it in step
  with project 6. `projects.sh build` is the from-scratch fallback.
- **Mutations are not idempotent.** `copy`, `draft-create`, `convert-draft`,
  `create-sub-issue` and `pr-create` create a new
  object each run; skills must never retry them, only follow-up steps such as
  `link` or `set-status`. Status is set last and read back, because board
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
- All eight delivery skills exist, plus `help` and `update`. The skills after
  `create-item` find an item's pull request by its branch name,
  `feature/<issueNumber>-<slug>`, which `develop` creates: keep that pattern.
- Check a changed skill with Skill Creator's validator, from the skill-creator
  plugin's folder: `python3 -m scripts.quick_validate <path-to-skill>`.

## Releasing a change

1. Bump `version` in `.claude-plugin/plugin.json` **and** the version badge in
   `README.md`. Without a bump, `vibe-engineering:update` won't fetch the change.
2. Keep `README.md`, `docs/concept.md`, `docs/roadmap.md` and the hand-written
   `skills/help/assets/help.html` consistent with which skills exist.
3. `description`/`displayName` appear in both `plugin.json` and
   `marketplace.json`; the marketplace entry wins, so change both together.
4. Run `claude plugin validate . --strict`.

Commit messages follow the existing style: a short imperative summary, with
`, release X.Y.Z` appended when the version is bumped.
