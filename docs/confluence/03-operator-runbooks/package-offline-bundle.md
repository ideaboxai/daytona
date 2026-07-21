---
title: Package the offline bundle
labels: [byoc, operator, air-gapped]
---

> Source: generated from `docs/confluence/03-operator-runbooks/package-offline-bundle.md`. Ported from `BYOC-DELIVERY.md` §4 + `scripts/fork/byoc-bundle.sh`. Edit in git, not in Confluence.

# Package the offline bundle

Air-gapped clients cannot pull from our registry, so ship the images **in the bundle**.
Run `byoc-bundle.sh` **after** the from-source images exist (§3 — present locally or
pulled) and after `byoc-release.sh` has written the source archive + offer under
`dist/byoc/<client>/...`.

```bash
CLIENT=<slug> \
FORK_REGISTRY=<acct>.dkr.ecr.<region>.amazonaws.com/<namespace> \
FORK_TAG=byoc-<slug>-<date>-<sha> \
BYOC_DIR=dist/byoc/<slug>/<date>-<sha> \
  ./scripts/fork/byoc-bundle.sh
```

Produces one file — `dist/byoc/<slug>/daytona-<slug>-<tag>.bundle.tar.gz` (+ `.sha256`) —
containing `images.tar` (all 10 images), the compose + configs, `install.sh`, and the
AGPL source archive + written offer. The client extracts it and runs `./install.sh`
(loads images, prompts ~6 settings, generates secrets, brings up).

## Architecture

`docker save` captures the **local** platform only — build/pull for the client's arch
(default amd64). For a mixed fleet, run once per arch.

## What goes in the bundle
- `images.tar` — all 10 images (4 from-source `daytona-*` + 6 third-party), plus `IMAGES.txt`.
- Compose + configs: `docker-compose.yaml`, the `ec2-http`, `hardening`, and `registry`
  overrides, `.env.example`, `CLIENT-INSTALL.md`, and the `dex` + `otel` config dirs.
- The Postgres CA bundle at `docker/certs/rds-ca-bundle.pem` (repo-provided, else fetched
  from Amazon at pack time) so RDS+TLS works air-gapped.
- `install.sh` (rendered with the registry + tag) and `seed-registry.sh`.
- `README.txt`, the AGPL `daytona-src-*.tar.gz` (+ `.sha256`) and `WRITTEN_OFFER.txt`.

## Delivery

Hand over the single bundle + `.sha256`. The client experience:

```
tar xzf daytona-<client>-<tag>.bundle.tar.gz && cd daytona-<client>-<tag>
./install.sh          # loads images, ~6 prompts, generates secrets, brings up
```

No git, no build, no registry access. See the full comparison in
**[Delivery scenarios](../02-delivery-scenarios)** and the client guide
**[Air-gapped — offline bundle](../04-client-guides/airgapped-offline-bundle)**. Clients
with an internal registry seed it once (`./seed-registry.sh`) instead of loading on every
node.
