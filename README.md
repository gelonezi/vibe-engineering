# vibeeng

Vibe engineering skills for [Claude Code](https://claude.com/claude-code).
The repository is a Claude Code plugin named `vibeeng`, so every skill in it
is called `vibeeng:<skill>`.

## Install

In Claude Code:

```
/plugin marketplace add gelonezi/vibeeng
/plugin install vibeeng@vibeeng
```

## Skills

| Skill                  | What it does                                                                                                                                                             |
|------------------------|--------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `vibeeng:create-board` | Creates a GitHub Projects board for iterative development (Draft → Done columns, iterations, estimates, six views) for your account, an organization, or a repository. |

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
  plugin.json          plugin manifest (name: vibeeng)
  marketplace.json     lets this repo be added as a plugin marketplace
skills/
  <skill-name>/
    SKILL.md           instructions Claude follows
    scripts/           helper scripts the skill runs
    references/        specs and docs the skill reads when needed
```

## Maintainers: the board template

`vibeeng:create-board` copies the public project titled **Iterative
development** in the `gelonezi` account. To publish or refresh it from the
reference board (`se-oriente-solucoes`, project 1), run:

```bash
cd skills/create-board/scripts
src=$(bash projects.sh get se-oriente-solucoes 1 | cut -f1)
owner=$(bash projects.sh owner gelonezi | cut -f1)
new=$(bash projects.sh copy "$owner" "$src" "Iterative development")
bash projects.sh set-public "$(echo "$new" | cut -f1)" true
echo "$new"
```

Keep exactly one public project with that title in the account, or set
`VIBEENG_TEMPLATE_NUMBER` to choose one.
