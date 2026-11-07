---
name: update
description: Update the installed vibe-engineering plugin to the latest published version and report what changed. Use when the user asks to update, upgrade, refresh or auto-update vibe-engineering or its skills, asks whether a newer version exists, or a skill behaves differently from its docs.
---

# vibe-engineering:update

Updates this plugin from its marketplace, then compares the installed copy with
what's published on GitHub.

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
