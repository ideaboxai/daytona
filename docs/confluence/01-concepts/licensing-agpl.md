---
title: Licensing model — AGPL server + proprietary app
labels: [byoc, agpl, explanation]
---

> Source: generated from `docs/confluence/01-concepts/licensing-agpl.md`. Edit in git, not in Confluence.

# Licensing model — AGPL server + proprietary app

Every BYOC delivery hands a client software under **two different licenses**, kept
apart by a deliberate boundary. Getting this right is what lets our app stay
proprietary while we ship an AGPL server.

## The model (read once)

Source: `BYOC-DELIVERY.md` §0.

```
Client licenses OUR app (proprietary)
        │  app calls Daytona SDK  ← Apache-2.0, over API — permissive
        ▼
Daytona sandbox SERVER (AGPL-3.0)  ← we deliver + they run as infra
```

- Only the **Daytona server** is AGPL-3.0. `LICENSE` in the repo is the unmodified
  **GNU Affero General Public License, Version 3**.
- Our app uses the **Daytona SDK over the API** — Apache-2.0, a permissive boundary —
  so the copyleft does **not** reach the app. The app stays proprietary.
- **Never** weld app code into the server. Integrate only via the SDK/API. Keeping
  proprietary code out of `apps/`/`libs/` is what keeps that boundary intact.

## Delivering the server is "conveying"

Handing the server to a client is *conveying* under AGPL-3.0, which means the client
must receive the **Corresponding Source** of the exact version they run. So **every
delivery** ships, alongside the deployment:

- **`daytona-src-<client>-<sha>.tar.gz`** (+ `.sha256`) — the AGPL Corresponding
  Source of the exact tagged commit (it contains `docker/`). The **git tag**
  `byoc/<client>/<date>-<sha>` is the source of truth; the archive regenerates
  byte-identical from it.
- **`WRITTEN_OFFER.txt`** — the AGPL §6 written-offer notice.

`scripts/fork/byoc-release.sh` automates this: it tags the commit, `git archive`s the
source, renders the written offer + sha256, appends the `BYOC_LEDGER.md` compliance
row, and builds/pushes the images.

## Only the four server images are the AGPL artifact

The provenance split from [Registries & image provenance](registries-provenance) *is*
the license boundary:

- The **four from-source server images** — `daytona-api`, `daytona-proxy`,
  `daytona-runner`, `daytona-ssh-gateway` — are the AGPL artifact. They must be built
  **from source** at the tagged commit (not the raw upstream mirror, which carries no
  AGPL provenance), and they are what the Corresponding Source archive covers.
- The **six third-party images** (dex, minio, otel-collector, registry, registry-ui,
  jaeger) carry their **own upstream licenses**. They are dependencies of the
  deployment, not our AGPL artifact, and are not covered by our source archive.

## Compliance checklist (per delivery)

From `BYOC-DELIVERY.md`:

- [ ] Images built **from source** at the tagged commit (not the mirror).
- [ ] `WRITTEN_OFFER.txt` + source archive + `.sha256` delivered **with** the deployment.
- [ ] `LICENSE` (AGPL-3.0) present in the archive (it is — unmodified).
- [ ] No proprietary app code in the AGPL server (SDK/API boundary intact).
- [ ] `BYOC_LEDGER.md` row committed (who got which tag/commit, when).
- [ ] Commercial license for our app papered separately (counsel) — AGPL governs only
      the sandbox server.

## Upgrades keep the obligation

An upgrade cuts a new release at the new commit → new tag, images, and source archive.
The client bumps `FORK_TAG`, pulls, and brings up; the api migrates on start. Give
them the **new** source archive (the Corresponding Source for the new version) and keep
the ledger row.

---

See **[Registries & image provenance](registries-provenance)** for how the four AGPL
images are built and stored, and **[Delivery scenarios](../02-delivery-scenarios)** for
how the source archive and written offer travel with each delivery path.
