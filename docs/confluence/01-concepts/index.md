---
title: Concepts
labels: [byoc, explanation]
---

> Source: generated from `docs/confluence/01-concepts/index.md`. Edit in git, not in Confluence.

# Concepts

The **why** behind a Daytona BYOC delivery — the shape of the system, where its
images come from, and the licensing model that governs the hand-off. Read these
before the [delivery scenarios](../02-delivery-scenarios) and the operator
runbooks: they explain the constraints those how-to pages take as given.

- **[Architecture](architecture)** — the ten Docker services and what each does, the
  privileged Docker-in-Docker *runner* that keeps the deployment on Docker Compose
  (not Kubernetes), the external Postgres + Redis, and the host prerequisites
  (`mount-s3`, `/dev/fuse`) and ports.
- **[Registries & image provenance](registries-provenance)** — the two ECR
  registries images land in, the 4 from-source (AGPL) images vs the 6 third-party
  mirrored ones, the deliberately irregular third-party repo names kept in lockstep,
  and why the all-from-ECR scenario needs the mirror.
- **[Licensing model — AGPL server + proprietary app](licensing-agpl)** — the
  AGPL-3.0 sandbox server vs our proprietary copilot app across the Apache-2.0 SDK
  boundary, and why every delivery must ship the Corresponding Source archive plus a
  written offer.
