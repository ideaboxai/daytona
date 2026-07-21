---
title: Image list & tags
labels: [byoc, reference]
---

> Source: generated from `docs/confluence/05-reference/image-list.md`. Edit in git, not in Confluence.

# Image list & tags

The stack is **10 images**: 4 Daytona **server** images we build, and 6 **third-party**
images we mirror. In a single-registry deploy all 10 live in ECR under one namespace
(`${FORK_REGISTRY}`, e.g.
`120354378950.dkr.ecr.us-east-1.amazonaws.com/ideaboxai-platform-core`). ECR repo names
below are the path appended to `${FORK_REGISTRY}`.

> ECR repo names are **deliberately irregular** — jaeger keeps its org prefix
> (`jaegertracing/all-in-one`), while dex, minio, otel, and registry-ui dropped theirs.
> Do not normalise them; pushes would land in repos that don't exist.

## Daytona server images (4) — AGPL, built from source

These are the AGPL-3.0 artifact covered by the client's source archive. Built from
source via `scripts/fork/build-push.sh` and pushed to ECR at the release tag
(`${FORK_TAG}`). The base `docker-compose.yaml` names them as Docker Hub
`daytonaio/daytona-*`; the `ec2-http` override repoints them to
`${FORK_REGISTRY}/daytona-*:${FORK_TAG}`.

| Service | Base compose image | ECR repo | Tag | Provenance |
|---|---|---|---|---|
| api | `daytonaio/daytona-api` | `daytona-api` | `${FORK_TAG}` | AGPL from-source |
| proxy | `daytonaio/daytona-proxy` | `daytona-proxy` | `${FORK_TAG}` | AGPL from-source |
| runner | `daytonaio/daytona-runner` | `daytona-runner` | `${FORK_TAG}` | AGPL from-source |
| ssh-gateway | `daytonaio/daytona-ssh-gateway` | `daytona-ssh-gateway` | `${FORK_TAG}` | AGPL from-source |

`FORK_TAG` example: `fork-YYYYMMDD-<shortsha>` (or a BYOC release tag such as
`byoc-<client>-<date>-<sha>`). Tag prefixes mark provenance: `fork-` from source,
`hub-` from a straight mirror, `wrap-` from a re-based wrapper.

## Third-party images (6) — mirrored

Copied manifest-for-manifest into ECR via `scripts/fork/mirror-thirdparty.sh` (or
`seed-registry.sh` for a client's own registry), preserving every architecture. Not
from-source; not part of the AGPL Corresponding Source. The `registry` override repoints
each to `${FORK_REGISTRY}/<repo>:<tag>`.

| Service | Upstream image:tag | ECR repo:tag | Provenance |
|---|---|---|---|
| dex | `dexidp/dex:v2.42.0` | `dex:v2.42.0` | mirrored |
| registry-ui | `joxit/docker-registry-ui:main` | `docker-registry-ui:main` | mirrored (mutable tag) |
| registry | `registry:2.8.2` | `registry:2.8.2` | mirrored |
| jaeger | `jaegertracing/all-in-one:1.67.0` | `jaegertracing/all-in-one:1.67.0` | mirrored (keeps org prefix) |
| minio | `minio/minio:latest` | `minio:latest` | mirrored (mutable tag) |
| otel-collector | `otel/opentelemetry-collector-contrib:0.138.0` | `opentelemetry-collector-contrib:0.138.0` | mirrored |

> `minio:latest` and `docker-registry-ui:main` are **mutable** upstream tags — what you
> mirror is whatever they point at right now. The mirror captures each digest so the
> compose override can pin `@sha256:...`.

See **[Compose files & overrides](compose-files)** for how the `ec2-http` and `registry`
overrides repoint these images, and **[Environment variables → Fork image
registry](environment-variables)** for `FORK_REGISTRY` / `FORK_TAG`.
