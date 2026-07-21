---
title: Cut a release
labels: [byoc, operator, agpl]
---

> Source: generated from `docs/confluence/03-operator-runbooks/cut-a-release.md`. Ported from `BYOC-DELIVERY.md` §2 + `scripts/fork/byoc-release.sh`. Edit in git, not in Confluence.

# Cut a release

Cut **one** immutable deploy point for a client and produce the AGPL-3.0 Corresponding
Source handoff for the Daytona **server** we convey to them. `byoc-release.sh` tags the
commit, `git archive`s the source, renders the written offer + sha256, appends the ledger
row, and (unless `SKIP_IMAGES=1`) builds + pushes the images.

## Prerequisites
- Clean checkout on the commit you want to ship — `byoc-release.sh` refuses a dirty tree.
- The client's slug (lowercase `a-z0-9-`).

## 1. Bump VERSION

The repo-root `VERSION` file is the single source of truth for the image tag the OIDC
workflow builds (semver `MAJOR.MINOR.PATCH`). Bump and commit it before cutting a release
so the release commit carries the version you intend to ship. `byoc-release.sh` tags by
commit sha, not by `VERSION` — see **[Build & push server images to ECR (OIDC)](build-push-images)**
for how the version tag is used.

## 2. Run byoc-release.sh

```bash
# from a clean checkout, on the commit you want to ship:
CLIENT=<slug> ./scripts/fork/byoc-release.sh          # full: tag + source + offer + images
# or, source/offer only (validate first, images later):
CLIENT=<slug> SKIP_IMAGES=1 ./scripts/fork/byoc-release.sh
```

A full run needs `CLIENT_REGISTRY` (or `SKIP_IMAGES=1`):

```bash
CLIENT=acmecorp \
CLIENT_REGISTRY=123456789.dkr.ecr.eu-west-1.amazonaws.com \
./scripts/fork/byoc-release.sh
```

What the four steps do:

1. Tag the immutable deploy point `byoc/<client>/<date>-<sha>` and push it to origin.
2. Bundle the Corresponding Source of that tag: `git archive` → `daytona-src-<client>-<sha>.tar.gz`.
3. Render `WRITTEN_OFFER.txt` (AGPL §6 notice) and write the `.sha256`.
4. Build + push the server images from the tag — skipped with `SKIP_IMAGES=1`; see
   **[Build & push server images to ECR (OIDC)](build-push-images)**.

It then appends a row to `BYOC_LEDGER.md` (creating the header if the file is missing).

## Notes
- The tag is **idempotent** — re-runs reuse it. So a `SKIP_IMAGES=1` run then a full run
  on the same commit is fine.
- The source archive **regenerates byte-identical** from the tag anywhere:
  `git archive --format=tar.gz --prefix="daytona-<sha>/" -o out.tar.gz byoc/<client>/<date>-<sha>`.
  The **tag** is the source of truth, not the file.
- Commit `BYOC_LEDGER.md` after each run.

## Outputs (per client)
| Artifact | Where |
|---|---|
| Git tag `byoc/<client>/<date>-<sha>` | pushed to origin |
| `daytona-src-<client>-<sha>.tar.gz` (+ `.sha256`) | `dist/byoc/<client>/<date>-<sha>/` (gitignored) |
| `WRITTEN_OFFER.txt` | same dir |
| Row in `BYOC_LEDGER.md` | committed |
