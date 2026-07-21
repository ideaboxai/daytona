---
title: Mirror third-party images to ECR
labels: [byoc, operator]
---

> Source: generated from `docs/confluence/03-operator-runbooks/mirror-thirdparty.md`. Ported from `.github/workflows/dev-ecr-mirror.yml` + `scripts/fork/mirror-thirdparty.sh`. Edit in git, not in Confluence.

# Mirror third-party images to ECR

Mirror the **6** third-party images the Daytona stack depends on into
`ideaboxai-platform-core/*`, so a Docker Hub outage — or an upstream tag being moved or
deleted — cannot block a deploy. Upstream `daytonaio/daytona` froze on 2026-06-11, which
is why this fork owns its whole image supply chain.

`docker buildx imagetools create` copies full manifest lists registry-to-registry without
pulling, preserving **every architecture** — so, unlike the from-source server images, the
mirror is arch-agnostic. A pull/tag/push loop would silently flatten each image to the
runner's arch.

## The 6 images and repo names

Repo names match the ECR repositories **exactly** and are deliberately **not** consistent
— jaeger keeps its org prefix while dex, minio and otel dropped theirs. Do not tidy these
into a pattern; pushes would land in repositories that do not exist. Keep in sync with
`docker/docker-compose.yaml`; the repo names match `docker/docker-compose.registry.override.yaml`.

| Upstream image | Our ECR repo name |
|---|---|
| `dexidp/dex:v2.42.0` | `dex` |
| `joxit/docker-registry-ui:main` | `docker-registry-ui` |
| `registry:2.8.2` | `registry` |
| `jaegertracing/all-in-one:1.67.0` | `jaegertracing/all-in-one` |
| `minio/minio:latest` | `minio` |
| `otel/opentelemetry-collector-contrib:0.138.0` | `opentelemetry-collector-contrib` |

`minio:latest` and `docker-registry-ui:main` are **mutable** tags — what you mirror is
whatever they point at right now. That is precisely why the digest is captured and pinned
in the compose override.

## Option A — the workflow (into platform-core, OIDC)

Manual-only by design: these images change a couple of times a year, so wiring them to
`push` would re-mirror six unchanged images on every commit.

```bash
gh workflow run dev-ecr-mirror.yml --ref main
```

- Run from `main` to actually push (deploy role); other branches use the read-only plan
  role and only print what would be mirrored.
- The `dry_run: true` input resolves and prints what would be mirrored without pushing.
- Onboarding prerequisites are identical to `dev-ecr-oidc.yml` — see
  **[Build & push server images to ECR (OIDC)](build-push-images)**.

Each mirrored image's digest is written to the run's step summary — it is what
`docker/docker-compose.registry.override.yaml` pins.

## Option B — the script (local run, any registry)

The script of record is `scripts/fork/mirror-thirdparty.sh`; it does the same thing for
local runs. Requires a docker login to the ECR **host** — not the namespace path:

```bash
aws ecr get-login-password --region us-east-1 \
  | docker login --username AWS --password-stdin 120354378950.dkr.ecr.us-east-1.amazonaws.com
```

```bash
FORK_REGISTRY=120354378950.dkr.ecr.us-east-1.amazonaws.com/ideaboxai-platform-core \
  ./scripts/fork/mirror-thirdparty.sh
```

It preflights that all 6 ECR repositories exist (ECR never auto-creates them on push),
mirrors each with `docker buildx imagetools create`, reads the digest back from the
registry, and writes them to `dist/fork-thirdparty-digests-<date>.txt`. Pin those into
`docker/docker-compose.registry.override.yaml`.
