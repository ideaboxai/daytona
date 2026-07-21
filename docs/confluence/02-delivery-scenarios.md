---
title: Delivery scenarios
labels: [byoc, reference, air-gapped, connected]
---

> Source: generated from `docs/confluence/02-delivery-scenarios.md`. Edit in git.

# Delivery scenarios

Every scenario ships the **same** compose, dex config, boot chain, and acceptance test.
**Only the image-source step differs.** Choose by answering two questions about the
client's host:

1. Does it have **outbound internet** at deploy time?
2. Can it reach **Docker Hub**, or only **our registry**?

## Decision table

| # | Client host | Image source at deploy | Deliver | Client guide |
|---|---|---|---|---|
| 1 | **Air-gapped**, single/few hosts | `docker load` from the bundle | 1.5 GB offline bundle + source | [4.1 Offline bundle](04-client-guides/airgapped-offline-bundle) |
| 2 | **Air-gapped**, runs an internal registry / fleet | Nodes pull from **their** registry (seeded once) | Bundle + `seed-registry.sh` | [4.2 Internal registry](04-client-guides/airgapped-internal-registry) |
| 3 | **Connected**, no Docker Hub | All 10 from **our ECR** | Grant ECR pull (all 10 repos) + deploy files | [4.3 All from vendor registry](04-client-guides/connected-all-from-registry) |
| 4 | **Connected**, has Docker Hub | 4 from **our ECR**, 6 from Docker Hub | Grant ECR pull (4 repos) + deploy files | [4.4 Registry + Docker Hub](04-client-guides/connected-registry-plus-hub) |

## How to choose (flow)

```
Is the host air-gapped (no outbound internet)?
├─ YES → one host?  ── YES → Scenario 1 (offline bundle)
│        └─ fleet / internal registry? → Scenario 2 (seed their registry)
└─ NO  → can it reach Docker Hub?
         ├─ NO  → Scenario 3 (all 10 from our ECR)   ← e.g. actian
         └─ YES → Scenario 4 (4 from ECR + 6 from Hub)
```

## Trade-offs

| Dimension | 1 Bundle | 2 Internal registry | 3 All-from-ECR | 4 ECR + Hub |
|---|---|---|---|---|
| Client-side friction | low (1 command) | medium (seed once) | low | low |
| Air-gap fit | ✅ native | ✅ native | ❌ needs internet to ECR | ❌ needs internet |
| Hand-off size | ~1.5 GB | ~1.5 GB | small (files + source) | small |
| Our prep | build → `docker save` | same + client seeds | build → push + **grant** | build → push + grant (4) |
| Docker Hub dependency | none | none | none | 6 images |
| Update story | ship new bundle | re-seed | bump tag, `pull` | bump tag, `pull` |

## What's identical across all four
- Base compose + `ec2-http` override (HTTP/IP) or your HTTPS reverse-proxy setup.
- External **Postgres + Redis** (their managed instances) — never bundled.
- The privileged **runner** (Docker-in-Docker) + `mount-s3` + `/dev/fuse` host needs.
- The **acceptance test**: boot to `🚀 Daytona API is running`, then create a sandbox.
- The **AGPL Corresponding Source** handoff (source archive + written offer).

See **[Concepts → Registries & provenance](01-concepts/registries-provenance)** for why
scenario 3 needs the 6 third-party images mirrored into our ECR, and
**[Operator runbooks](03-operator-runbooks)** for how we produce each artifact.
