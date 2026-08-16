---
name: befold-review
description: Open a file in the befold viewer so the user
  sees it rendered, not raw source. befold renders
  Markdown, Mermaid, SVG, HTML, CSV/TSV, images, PDF and
  source code. Use when you wrote or updated such a file
  and are about to ask the user to review it.
---

## When to use

Just before asking the user to review a file you wrote or
updated - design docs (.md), diagrams (.mmd, .svg), pages
(.html), data (.csv, .tsv), images, PDFs, or source files.
Not when the user asks you to review a file - you read the
source directly.

## Requirements

The `befold` CLI. It ships with the befold app and is
installed from the app's App menu > Install Command Line
Tool.

## Steps

1. Collect the paths the user should look at.
2. Right before the review request, open them:

   command -v befold >/dev/null 2>&1 \
     && befold PATH [PATH ...]

3. If befold is missing or fails, skip it and ask for
   the review as usual. The files stay watched, so your
   later edits refresh the same window.
