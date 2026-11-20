---
name: update
description: Update the installed vibe-engineering plugin to the latest published version, report what changed, and check that its companion plugins (superpowers, code-review, claude-md-management, skill-creator) are installed. Use when the user asks to update, upgrade, refresh or auto-update vibe-engineering or its skills, asks whether a newer version exists, asks whether the setup or the companion plugins are complete, or a skill behaves differently from its docs.
---

# vibe-engineering:update

Updates this plugin from its marketplace, compares the installed copy with
what's published on GitHub, then checks the companion plugins.

Run `bash <skill-dir>/../../scripts/update.sh` and read its `KEY=value` lines.
Don't run `claude plugin` commands yourself: the script runs them in the right
order and reports the result.

## Report

- **`STATUS` is not `ok`:** show the `FIX` line as a command the user can run,
  explain it in one sentence, and pass on any `ERROR` line. Don't work around it.
- **`UPDATE_OUTCOME=up_to_date` and `BEHIND=false`:** say the plugin is up to
  date, with `NEW_VERSION`.
- **Any other `UPDATE_OUTCOME`:** say it went from `OLD_VERSION` to
  `NEW_VERSION`, list the `CHANGE` lines, and tell the user to restart Claude
  Code (`RESTART=required`). This session keeps the old copy, so don't try the
  new skills here.
- **`BEHIND=true`:** the published plugin has commits that the installed version
  number doesn't cover, so the update didn't fetch them. List the `CHANGE`
  lines, show the `FIX` line, and run it only if the user agrees: it uninstalls
  and reinstalls the plugin. Then say a restart is needed.
- **`REMOTE_SHA=unknown`:** the GitHub CLI isn't available, so say the published
  state couldn't be compared, and report the update result alone.

Keep it to a few lines, with the `MESSAGE` line only when it adds something.

## Check the companion plugins

This plugin comes with four others. Some skills hand part of their work to
`superpowers`, `code-review` and `claude-md-management`, and `skill-creator` is
there for the project's own skills. Claude Code installs them together with
this plugin, but a copy turned on from claude.ai, or an older Claude Code, may not
have them, or may have one turned off.

Run `bash <skill-dir>/../../scripts/companions.sh` and read its `KEY=value` lines.

- **`STATUS=ok`:** say nothing.
- **`STATUS=missing`:** name each `COMPANION` that is `missing` or `disabled`, and
  show its `FIX` line as a command the user can run. Say that the skills still
  work without it, and do that part themselves. Run a `FIX` only if the user agrees.
- **`STATUS=unknown`:** pass on the `MESSAGE` line in one sentence.
