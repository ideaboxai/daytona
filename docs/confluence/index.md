---
title: Daytona Sandbox — BYOC Delivery
labels: [byoc, overview]
---

> Source: generated from `docs/confluence/index.md` in the daytona repo. Edit there, not in Confluence.

# Daytona Sandbox — BYOC Delivery

This space is the single source of truth for delivering the **Daytona sandbox server**
to enterprise **BYOC** (bring-your-own-cloud) clients — how we cut a release, get the
images to the client, and how the client installs, verifies, and operates it.

## Who this is for
- **Operators (us)** — cutting releases, pushing images, granting access, rehearsing,
  supporting clients. Start at **[Operator runbooks](03-operator-runbooks)**.
- **Clients (them)** — installing on their own infrastructure. Hand them the relevant
  page under **[Client install guides](04-client-guides)**.

## What Daytona is (30 seconds)
- The **Daytona sandbox server** — ~10 Docker services (api, proxy, a privileged
  Docker-in-Docker *runner*, dex, minio, an internal registry, otel/jaeger) plus the
  client's **own external Postgres + Redis**. Licensed **AGPL-3.0** → every delivery
  ships Corresponding Source.
- It runs the sandboxes our **copilot app** (proprietary, Apache-2.0 SDK boundary)
  drives over the API. The app stays ours; the sandbox server is what we deliver here.
- Full detail: **[Concepts → Architecture](01-concepts/architecture)** and
  **[Licensing model](01-concepts/licensing-agpl)**.

## Pick your delivery scenario
Which path a client takes depends on **one thing: how images reach their host.**

| Client situation | Path | Guide |
|---|---|---|
| No internet at deploy (air-gapped) | Offline bundle (`docker load`) | [4.1 Air-gapped — offline bundle](04-client-guides/airgapped-offline-bundle) |
| Air-gapped, but runs an internal registry / a fleet | Seed their registry, nodes pull | [4.2 Internal registry](04-client-guides/airgapped-internal-registry) |
| Pulls from our ECR, **can't** reach Docker Hub | All 10 from our registry | [4.3 Connected — all from vendor registry](04-client-guides/connected-all-from-registry) |
| Pulls from our ECR, **has** Docker Hub | 4 from our ECR + 6 from Hub | [4.4 Connected — registry + Docker Hub](04-client-guides/connected-registry-plus-hub) |

Full comparison + how to choose: **[Delivery scenarios](02-delivery-scenarios)**.

## Space map
- **[1. Concepts](01-concepts)** — architecture, registries & provenance, licensing *(why)*
- **[2. Delivery scenarios](02-delivery-scenarios)** — the decision matrix *(reference)*
- **[3. Operator runbooks](03-operator-runbooks)** — cut, build, mirror, bundle, grant, rehearse, upgrade *(how-to, internal)*
- **[4. Client install guides](04-client-guides)** — the four deliverable install paths *(how-to, client)*
- **[5. Reference](05-reference)** — prerequisites, env vars, image list, compose files *(reference)*
- **[6. Verify & operate](06-verify-operate)** — acceptance test, backup, upgrade *(how-to)*
- **[7. Troubleshooting](07-troubleshooting)** — failures we actually hit *(how-to)*

## Conventions
Every page is generated from the git repo (banner at top names the source file). Edit in
git; Confluence is the published mirror. See **[Publishing](PUBLISHING)** for how this
space is built.
