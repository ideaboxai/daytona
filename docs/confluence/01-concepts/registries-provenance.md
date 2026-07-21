---
title: Registries & image provenance
labels: [byoc, explanation]
---

> Source: generated from `docs/confluence/01-concepts/registries-provenance.md`. Edit in git, not in Confluence.

# Registries & image provenance

Upstream `daytonaio/daytona` froze on **2026-06-11**, so this fork builds its own
service images and mirrors its third-party ones rather than depending on Docker Hub.
All ten images live in **our ECR** under one namespace. This page explains where the
images come from, how they get there, and why the provenance split matters.

> Not the same as the in-stack `registry`. The compose stack also runs an internal
> `registry` service (`registry:6000`) that the api uses as its transient/internal
> registry for **sandbox snapshots** at runtime. That is a runtime concern (see
> [Architecture](architecture)) — it is *not* where the ten delivery images come from.

## The two ECR registries images land in

Both are "our ECR"; `FORK_REGISTRY` **must include the namespace path**, not just the
host — the scripts append `/<repo>` to it.

| Registry | Value | How images land | Notes |
|---|---|---|---|
| **platform-core** (canonical build store) | `120354378950.dkr.ecr.us-east-1.amazonaws.com/ideaboxai-platform-core` | GitHub Actions workflow `dev-ecr-oidc.yml` builds from source and pushes via **OIDC** | OIDC-only, **no local push keys** — a laptop cannot `docker push` here. |
| **ideaboxai** (push-creds account) | `304038454586` / `ideaboxai` namespace | Run `build-push.sh` directly, **from the tagged commit** | An account we hold push creds for. `FORK_REGISTRY` can also point at a client's own ECR. |

Log in to the **host** only (not the namespace path), e.g.:

```bash
aws ecr get-login-password --region us-east-1 \
  | docker login --username AWS --password-stdin 120354378950.dkr.ecr.us-east-1.amazonaws.com
```

> The #1 gotcha: `build-push.sh` reporting *"Missing ECR repositories"* when the repos
> clearly exist almost always means you are authed to the **wrong AWS account** —
> `describe-repositories` queries the *caller's* account. Check `aws sts
> get-caller-identity` matches the registry account first. (ECR never auto-creates
> repositories on push; DevOps creates them up front.)

## The provenance split: 4 from-source vs 6 third-party

The ten images divide by where they come from — and this line is the same one that
draws the [AGPL boundary](licensing-agpl).

### 4 from-source images (the AGPL artifact)

`daytona-api`, `daytona-proxy`, `daytona-runner`, `daytona-ssh-gateway` — built **from
source at the tagged commit** by `build-push.sh` and hardened (non-root where
possible; the runner stays root by design for DinD). Because `build-push.sh` compiles
locally, these are **single-arch** and must match the deploy target — it defaults to
`linux/amd64`; override with `TARGET_PLATFORM=linux/arm64`. These four are the AGPL-3.0
Corresponding-Source artifact; they must be from source, never the raw upstream mirror.

### 6 third-party images (mirrored)

`dex`, `registry-ui`, `registry`, `minio`, `jaeger`, `otel-collector` — mirrored into
our ECR by `scripts/fork/mirror-thirdparty.sh`. It uses `docker buildx imagetools
create`, which copies the full **manifest list** registry-to-registry without pulling,
so **every architecture is preserved** (a pull/tag/push loop would silently flatten to
the build machine's arch). Mirroring means a Docker Hub outage — or an upstream tag
being moved or deleted — can't block a fresh deploy.

Two sources are **mutable** tags — `minio:latest` and `docker-registry-ui:main` — so a
mirror captures whatever they point at *right now*. That is exactly why the script
records each pushed **digest** (to `dist/fork-thirdparty-digests-<date>.txt`) to pin
into `docker/docker-compose.registry.override.yaml`.

## The deliberately irregular third-party repo names

The ECR repo names are **not** consistent, on purpose: jaeger keeps its org prefix
while dex, minio, and otel dropped theirs. Do not tidy them into a pattern — pushes
would land in repos that don't exist.

| Upstream image | Our ECR repo |
|---|---|
| `dexidp/dex:v2.42.0` | `dex` |
| `joxit/docker-registry-ui:main` | `docker-registry-ui` |
| `registry:2.8.2` | `registry` |
| `jaegertracing/all-in-one:1.67.0` | `jaegertracing/all-in-one` |
| `minio/minio:latest` | `minio` |
| `otel/opentelemetry-collector-contrib:0.138.0` | `opentelemetry-collector-contrib` |

These six names must stay in **lockstep** across the places that reference them, or
pulls and pushes break:

- `docker/docker-compose.registry.override.yaml` — repoints the six images to
  `${FORK_REGISTRY}/<repo>:<tag>`
- `scripts/fork/mirror-thirdparty.sh` — mirrors upstream → our ECR
- `seed-registry.sh` — seeds a client's own registry (air-gapped fleet path)
- the ECR repositories DevOps created

## Why the all-from-ECR scenario needs the mirror

A connected client that **cannot reach Docker Hub** (e.g. actian) must pull **all ten**
images from our ECR. The four server images are already built there; the six
third-party images are only there **if they were mirrored**. So `mirror-thirdparty.sh`
puts all ten in one place, and the client deploys with `IMAGE_SOURCE=registry` — which
adds `docker-compose.registry.override.yaml` so every image resolves to
`${FORK_REGISTRY}`. Without the mirror, deploy would still reach for the six upstream
images on Docker Hub, which that client cannot reach. This is
[scenario 3](../02-delivery-scenarios) in the delivery matrix.

---

See **[Licensing model](licensing-agpl)** for why only the four from-source images are
the AGPL artifact, and **[Delivery scenarios](../02-delivery-scenarios)** for how each
scenario sources its images.
