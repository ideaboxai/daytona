# Publishing these docs to Confluence

This directory is the **source** for the Confluence space *Daytona Sandbox — BYOC
Delivery*. The folder tree here maps 1:1 to the Confluence page hierarchy. Author and
review here (git-versioned truth); publish to Confluence as a read-only mirror.

> Why keep the source in git: standard practice for self-hosted delivery runbooks is a
> version-controlled source of truth, not docs that live only inside the platform.

## Layout → page tree

Each folder is a parent page (its `index.md`); each `*.md` is a child page. Numeric
prefixes control order and are stripped from titles. Titles + labels come from the YAML
frontmatter at the top of every file:

```yaml
---
title: Air-gapped — offline bundle
labels: [byoc, client, air-gapped]
---
```

## Option A — md2conf (scripted, repeatable; recommended for CI)

```bash
pip install md2conf
export CONFLUENCE_DOMAIN=<your-org>.atlassian.net
export CONFLUENCE_USER=<you>@<org>.com
export CONFLUENCE_API_KEY=<atlassian-api-token>     # id.atlassian.com/manage/api-tokens
export CONFLUENCE_SPACE_KEY=<SPACEKEY>              # create the empty space first

# dry run (renders, no writes):
python -m md2conf docs/confluence --dry-run
# publish the whole tree (idempotent — re-run to update):
python -m md2conf docs/confluence
```

md2conf creates/updates pages, preserves the hierarchy, and reorders to match the file
order. Re-running after edits updates pages in place (no duplicates).

## Option B — Confluence Universal Importer (no code)

Confluence Cloud → your space → **… → Import → Universal Importer → Markdown**, then
drag this `docs/confluence/` folder. It recreates the tree in one pass. Good for the
first load; use Option A for ongoing sync.

## Conventions

- **Source banner:** every page starts with a note pointing back to the repo path it was
  generated from — edits happen in git, not in Confluence.
- **Labels:** `byoc`, `operator`, `client`, `air-gapped`, `connected`, `reference`,
  `agpl`, `troubleshooting`.
- **Client hand-off:** export pages under `04-client-guides/` + `05-reference/` +
  `06-verify-operate/` to a single PDF per delivery.
- **Screenshots/diagrams:** put under `_assets/` and reference relatively; md2conf uploads
  them as attachments.
