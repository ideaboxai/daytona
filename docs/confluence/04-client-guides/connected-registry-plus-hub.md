---
title: Connected — vendor registry + Docker Hub
labels: [byoc, client, connected]
---

> Source: generated from `docs/confluence/04-client-guides/connected-registry-plus-hub.md`. Ported from `docker/CLIENT-INSTALL-CONNECTED.md`. Edit in git, not in Confluence.

# Connected — vendor registry + Docker Hub

You received a Daytona server deployment for a host **with outbound internet** that can
reach **Docker Hub**. This guide brings it up by pulling the **4 Daytona server images
from the vendor's registry** (our ECR) and the **6 third-party images from Docker Hub**
— no registry override, no third-party mirror.

> This page is the shorter sibling of
> [Connected — all 10 from the vendor registry](connected-all-from-registry). The
> **What you received**, **Prerequisites**, and **Bootstrap a fresh host** steps are
> identical — read them there. The only difference is that here you leave off the
> `registry` override, so the 6 third-party images come from Docker Hub. If your host
> **cannot** reach Docker Hub, use the all-from-registry page instead. If your host is
> **air-gapped**, use the [Air-gapped — offline bundle](airgapped-offline-bundle).

## Prerequisites (shared)

Same as [Connected — all 10 from the vendor registry](connected-all-from-registry#prerequisites):
a Linux host with **outbound internet** + Docker + compose, **AWS CLI** with your
credentials, your own external **Postgres** (Daytona's own DB) and **Redis**
(non-cluster, DB 0), the runner-host needs (`/dev/fuse` + `mount-s3` at
`/usr/bin/mount-s3`), and open inbound ports `3002`, `4003`, `5556`, `2222`.

**One extra requirement for this path:** the host must be able to reach **Docker Hub**,
since the 6 third-party images pull from there.

## Quick install (recommended)

`install.sh` works for the connected path too — when there is **no `images.tar`**
beside it, it skips the offline load and expects the images to come from the registry.
So: log in to the vendor registry, then run it plain (no `IMAGE_SOURCE=registry`).

```bash
# 1. Log in to the vendor registry (your creds; pull is authorized by the vendor)
aws ecr get-login-password --region <REGION> \
  | docker login --username AWS --password-stdin <REGISTRY_HOST>

# 2b. …if your host CAN reach Docker Hub: the 4 server images come from the
#     vendor registry, the 6 third-party from Docker Hub.
./install.sh
```

When prompted, use the vendor's registry host+namespace as the image source and this
host's address. **Pull happens on first `up`.** Without `IMAGE_SOURCE=registry`, only
the 4 server images resolve under your `FORK_REGISTRY`; the 6 third-party pull from
Docker Hub. Then jump to **Verify**.

## Manual install (alternative)

Follow steps 1–5 of the manual install in
[Connected — all 10 from the vendor registry](connected-all-from-registry#manual-install-alternative)
(extract the archive, log in to the vendor registry, create Daytona's database,
configure `docker/.env`, generate the IP-based dex config). The **only** difference is
step 6 — **drop** the `registry` override so the 6 third-party images pull from Docker
Hub:

```bash
CF="--env-file docker/.env \
  -f docker/docker-compose.yaml \
  -f docker/docker-compose.ec2-http.override.yaml"

docker compose $CF pull
docker compose $CF up -d
```
Without the `registry` override, only the 4 `daytona-*` server images come from the
vendor registry; the 6 third-party (`dex`, `minio`, `opentelemetry-collector-contrib`,
`docker-registry-ui`, `jaegertracing/all-in-one`, `registry`) pull from Docker Hub.

Then watch it come up and open the dashboard exactly as in steps 7–8 of the
all-from-registry guide.

## Verify (acceptance test)

Booting is necessary but not sufficient — confirm a sandbox actually works, since that
is what your application consumes. Follow the shared
**[Verify — acceptance test](../06-verify-operate/acceptance-test)**: check all
services are up, `curl http://<host>:3002/api/health` → `200`, then create a sandbox,
run a command in it, and delete it.

## Notes

- This is the **connected** path — it needs outbound internet at deploy to pull both
  the vendor images (ECR) and the third-party images (Docker Hub). Air-gapped hosts
  must use the offline bundle path in [Air-gapped — offline bundle](airgapped-offline-bundle).
- The four Daytona **server** images are the AGPL artifact covered by your source
  archive; the third-party images are their vendors' own.
