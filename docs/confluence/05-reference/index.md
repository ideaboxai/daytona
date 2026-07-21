---
title: Reference
labels: [byoc, reference]
---

> Source: generated from `docs/confluence/05-reference/index.md`. Edit in git, not in Confluence.

# Reference

Lookup tables for the self-hosted Daytona stack — the authoritative values you copy
into `docker/.env`, the ports you open, the images you pull, and the compose files
you apply. Every value here is ported verbatim from the deploy files under `docker/`.

- **[Prerequisites & ports](prerequisites-ports)** — host prerequisites (Docker +
  compose plugin, `/usr/bin/mount-s3`, `/dev/fuse`), the inbound ports table, and the
  external Postgres / Redis constraints.
- **[Environment variables (.env)](environment-variables)** — every variable from
  `docker/.env.example`, grouped by section, with what it's for and its example value.
- **[Image list & tags](image-list)** — all 10 images: the 4 Daytona server images
  (built from source) and the 6 third-party images (mirrored), with exact tags and ECR
  repo names.
- **[Compose files & overrides](compose-files)** — the base compose plus each override
  (ec2-http, registry, hardening, build): what it does, when to apply it, and the `-f`
  order.
