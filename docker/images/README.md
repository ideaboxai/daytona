# Service image wrappers

Thin `FROM daytonaio/daytona-*` wrappers that re-base the prebuilt upstream
images and replay this fork's non-root hardening (commit `edda70ca8`) **without
a from-source build**.

## Why these exist

There are three ways to get the four service images into our ECR. They are not
redundant — each trades something:

| Path | What it does | Hardening | Multi-arch | Provable commit (AGPL/BYOC) | Cost |
|------|--------------|-----------|-----------|-----------------------------|------|
| [`scripts/fork/build-push.sh`](../../scripts/fork/build-push.sh) | Builds from source | ✅ real Dockerfile | single-arch¹ | ✅ | heavy (Node/Go/Nx) |
| [`scripts/fork/mirror-daytona-hub.sh`](../../scripts/fork/mirror-daytona-hub.sh) | Straight copy of prebuilt images | ❌ none | ✅ preserved | ❌ | trivial |
| **wrappers** (`build-image-wrappers.sh`) | Re-base prebuilt + add `USER` | ✅ replayed | ✅ if built with buildx | ❌ | light |

¹ build-push.sh is single-arch because it compiles locally; add an arm64 runner

+ manifest merge for both.

The wrapper is the **middle path**: you get the non-root runtime hardening the
mirror can't give you, without waiting on the full build toolchain that
build-push.sh needs. It is the right default when hardening matters but you're
not shipping to a BYOC client.

## What each wrapper adds

Nothing but the hardening from `edda70ca8`, matched to each image's base:

+ **[api.Dockerfile](api.Dockerfile)** — `USER node` (uid 1000, already in `node:24-slim`).
+ **[proxy.Dockerfile](proxy.Dockerfile)** — `adduser appuser` + `USER appuser` (`alpine:3.22` has no non-root user).
+ **[ssh-gateway.Dockerfile](ssh-gateway.Dockerfile)** — same as proxy.
+ **[runner.Dockerfile](runner.Dockerfile)** — **nothing.** The runner must stay
  root: it hosts the privileged Docker-in-Docker daemon that runs sandboxes. It
  exists only so all four images come from one uniform pipeline. Isolation is at
  the sandbox boundary, not the runner's own user.

## Do NOT use these for BYOC client images

Like the mirror, a wrapper cannot prove which upstream commit its base came from
(`:latest` is a moving tag upstream stopped moving). AGPL's Corresponding Source
obligation wants that provenance for any image shipped to a client. Use
`build-push.sh` there.

## Build

Multi-arch (default — upstream bases are amd64 + arm64, so the wrapper stays so):

```bash
docker buildx create --use --name daytona-wrappers 2>/dev/null || true
docker run --privileged --rm tonistiigi/binfmt --install arm64   # QEMU for the cross leg

FORK_REGISTRY=120354378950.dkr.ecr.us-east-1.amazonaws.com/ideaboxai-platform-core \
  ./scripts/fork/build-image-wrappers.sh
```

Single-arch (faster, no QEMU — must match the deploy target):

```bash
PLATFORMS=linux/amd64 FORK_REGISTRY=... ./scripts/fork/build-image-wrappers.sh
```

Both write `dist/fork-wrapper-digests-*.txt`; pin those `@sha256` digests into
[`docker/docker-compose.registry.override.yaml`](../docker-compose.registry.override.yaml.example).
The `wrap-<date>-<sha>` tag prefix marks provenance (vs `fork-` from source,
`hub-` from the mirror).
