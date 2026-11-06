# vibe-engineering

Vibe engineering skills for [Claude Code](https://claude.com/claude-code).
This repository is a Claude Code plugin named `vibe-engineering`, so every
skill in it is called `vibe-engineering:<skill>`.

## Install

In Claude Code:

```
/plugin marketplace add gelonezi/vibe-engineering
/plugin install vibe-engineering@vibe-engineering
```

## Skills

| Skill                           | What it does                                                                                                                                                             |
|---------------------------------|--------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `vibe-engineering:create-board` | Creates a GitHub Projects board for iterative development (Draft → Done columns, iterations, estimates, six views) for your account, an organization, or a repository. |
| `vibe-engineering:create-item`  | Helps you shape a new idea and adds it to the board as a Draft item. |

The full flow, including the skills still to come, is in
[docs/concept.md](docs/concept.md).

## Requirements

- The [GitHub CLI](https://cli.github.com/), logged in with the `project` scope:

  ```bash
  gh auth login -s project
  ```

  If you're already logged in, add the scope with:

  ```bash
  gh auth refresh -s project
  ```

## Layout

```
.claude-plugin/
  plugin.json          plugin manifest (name: vibe-engineering)
  marketplace.json     lets this repo be added as a plugin marketplace
docs/
  concept.md           how the skills work together
scripts/               GitHub helper scripts shared by the skills
skills/
  <skill-name>/
    SKILL.md           instructions Claude follows
    references/        specs and docs the skill reads when needed
```

## Maintainers: the board template

`vibe-engineering:create-board` copies
[project 4 in the `gelonezi` account](https://github.com/users/gelonezi/projects/4),
which was made from GitHub's built-in **Iterative development** template, with a
Draft column added. It's public, so keep it free of real work. Changes made there
reach new boards only.

To copy a different project, set `VIBE_ENGINEERING_TEMPLATE_OWNER` and
`VIBE_ENGINEERING_TEMPLATE_NUMBER`.
