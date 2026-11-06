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

`vibe-engineering:create-board` copies the public project titled **Iterative
development** in the `gelonezi` account. To publish or refresh it from the
reference board (`se-oriente-solucoes`, project 1), run:

```bash
cd scripts
src=$(bash projects.sh get se-oriente-solucoes 1 | cut -f1)
owner=$(bash projects.sh owner gelonezi | cut -f1)
new=$(bash projects.sh copy "$owner" "$src" "Iterative development")
bash projects.sh set-public "$(echo "$new" | cut -f1)" true
echo "$new"
```

Keep exactly one public project with that title in the account, or set
`VIBE_ENGINEERING_TEMPLATE_NUMBER` to choose one.
