---
title: Client install guides
labels: [byoc, client]
---

> Source: generated from `docs/confluence/04-client-guides/index.md`. Edit in git.

# Client install guides

The four deliverable install paths. Give the client **one** of these — pick it from the
**[Delivery scenarios](../02-delivery-scenarios)** decision table. All four end at the
same **[acceptance test](../06-verify-operate/acceptance-test)** (boot + create a sandbox).

- **[4.1 Air-gapped — offline bundle](airgapped-offline-bundle)** — no internet at
  deploy; `docker load` from the bundle. The default for a single/few air-gapped hosts.
- **[4.2 Air-gapped / fleet — your own internal registry](airgapped-internal-registry)** —
  seed the client's internal registry once, nodes pull from it. For multiple nodes.
- **[4.3 Connected — all 10 from the vendor registry](connected-all-from-registry)** —
  the host pulls every image from our ECR; no Docker Hub. (e.g. actian.)
- **[4.4 Connected — vendor registry + Docker Hub](connected-registry-plus-hub)** — 4
  server images from our ECR, 6 third-party from Docker Hub.

Each guide is self-contained and PDF-exportable for hand-off. The authoritative in-bundle
copies live at `docker/CLIENT-INSTALL.md` and `docker/CLIENT-INSTALL-CONNECTED.md`.
