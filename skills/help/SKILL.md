---
name: help
description: Explain how vibe-engineering works by showing its illustrated help page. Use when the user asks how the system, the flow, the board or the skills work, what a skill does, how to get started, or asks for help, a guide, docs, an overview, a tutorial or an introduction to vibe-engineering.
---

# vibe-engineering:help

The help page is `assets/help.html`, next to this file. It's a single
self-contained file that works offline, and it's the full reference: the flow
across the board, every skill, how to get started, and the rules.

## 1. Show the page

Try these in order, and stop at the first that works:

1. If you have a tool that shows a local HTML file to the user, such as an
   artifact, preview or file-sending tool, use it with the page's path.
2. Otherwise run `bash <skill-dir>/scripts/open-help.sh`. It prints
   `PAGE=<path>` and `OPENED=true` or `OPENED=false`.
3. If the page wasn't opened, give the user the `PAGE` path to open themselves.

## 2. Answer the question

If the user asked something specific, answer it in a few lines from the page or
from [docs/concept.md](../../docs/concept.md), and say which section of the page
covers it. Don't paste the page into the chat.

If they only asked for help, say in one line what the page covers, and name the
best first step: `vibe-engineering:create-board` without a board, or
`vibe-engineering:create-item` with one.

## Keeping the page current

The page is written by hand. When a skill is added or changes, update it along
with `README.md` and `docs/concept.md`.
