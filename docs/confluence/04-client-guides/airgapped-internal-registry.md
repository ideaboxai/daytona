---
title: Air-gapped / fleet — your own internal registry
labels: [byoc, client, air-gapped]
---

> Source: generated from `docs/confluence/04-client-guides/airgapped-internal-registry.md`. Ported from `docker/CLIENT-INSTALL.md` (the "Deploy via your own internal registry" section) and `scripts/fork/templates/seed-registry.sh`. Edit in git, not in Confluence.

# Air-gapped / fleet — your own internal registry

If you run more than one node, or your nodes are configured to pull only from your
**internal registry** (common in locked-down networks), seed that registry once
instead of `docker load`-ing the tarball on every host. Afterwards every node pulls
**all 10 images** (4 Daytona server + 6 third-party) from your registry — no Docker
Hub, no vendor ECR at deploy.

This is a variant of the [Air-gapped — offline bundle](airgapped-offline-bundle) path:
the same offline bundle, the same external Postgres/Redis, the same runner host needs
(`/dev/fuse` + `mount-s3` at `/usr/bin/mount-s3`), and the same inbound ports (`3002`,
`4003`, `5556`, `2222`). Only the image-source step changes — you seed a registry once,
then point each node at it.

## Prerequisites

- The offline bundle, extracted, on a **seed host** that has the bundle **and** can
  reach your internal registry. `seed-registry.sh` must be run **inside the extracted
  bundle** (it needs `IMAGES.txt` and `images.tar`).
- Your **internal registry**, reachable from the seed host and from every deploy node.
  If it needs auth, `docker login <your-registry-host>` first. Some registries require
  repositories to be **precreated** — the registry must accept these repositories.
- On each deploy node: the standard runner-host prerequisites and open ports from the
  [offline-bundle guide](airgapped-offline-bundle#prerequisites), plus your own
  external **Postgres** and **Redis** (Daytona's own DB, Redis non-cluster on DB 0).

## 1. Seed your registry

Run **once**, from a host that has the bundle and can reach the registry. Log in first
if it needs auth:
```bash
docker login <your-registry-host>      # if required
./seed-registry.sh                     # asks for the registry host + namespace
```

`seed-registry.sh` reads `IMAGES.txt` (shipped in the bundle), loads `images.tar`,
retags each image to `<registry-prefix>/<leaf>`, and pushes it. It pushes **all 10
images** (4 Daytona server + 6 third-party) to `<registry-host>/<namespace>/...`. The
leaf paths match exactly what the compose overrides expect, so deploy needs only
`FORK_REGISTRY=<prefix>`. When it finishes it prints the `FORK_REGISTRY` and `FORK_TAG`
values to use, for example:

```
>> Done. All images pushed under: <registry-host>/<namespace>
>> Deploy config — set these in docker/.env (or answer them to install.sh):
     FORK_REGISTRY=<registry-host>/<namespace>
     FORK_TAG=<the server tag>
```

## 2. Deploy on each node

Pull everything from your registry, no tarball:
```bash
IMAGE_SOURCE=registry FORK_REGISTRY=<prefix from step 1> ./install.sh
```
`install.sh` skips the offline load and brings the stack up with the `registry`
override, so **all 10 images** come from your registry — no Docker Hub, no vendor ECR.
Then jump to **Verify**.

## Verify (acceptance test)

Booting is necessary but not sufficient — confirm a sandbox actually works, since that
is what your application consumes. On each node, follow the shared
**[Verify — acceptance test](../06-verify-operate/acceptance-test)**: check all
services are up, `curl http://<host>:3002/api/health` → `200`, then create a sandbox,
run a command in it, and delete it.
