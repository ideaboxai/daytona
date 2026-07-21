---
title: Operator runbooks
labels: [byoc, operator]
---

> Source: generated from `docs/confluence/03-operator-runbooks/index.md`. Ported from `BYOC-DELIVERY.md`. Edit in git, not in Confluence.

# Operator runbooks

How **we** produce and deliver a Daytona sandbox deployment to a client, step by step.
These are internal how-to runbooks — client-facing install steps live under
**[Client install guides](../04-client-guides)**.

Work them roughly in order for a first delivery: cut the release, get the images into
ECR, then package or grant pull depending on the
**[delivery scenario](../02-delivery-scenarios)**, rehearse, and finally handle upgrades
and revocation.

1. **[Cut a release](cut-a-release)** — bump `VERSION`, tag an immutable deploy point,
   and produce the AGPL Corresponding Source (source archive + written offer).
2. **[Build & push server images to ECR (OIDC)](build-push-images)** — run the
   `dev-ecr-oidc.yml` workflow to build the 4 server images from source and push to ECR.
3. **[Mirror third-party images to ECR](mirror-thirdparty)** — mirror the 6 third-party
   images into our ECR so no deploy depends on Docker Hub.
4. **[Package the offline bundle](package-offline-bundle)** — assemble the single
   air-gapped delivery bundle (all 10 images + compose + installer + source).
5. **[Grant a client ECR pull](grant-client-pull)** — cross-account repository policy so
   a connected client pulls from our ECR (all 10 repos, or just the 4 server images).
6. **[Dress-rehearse on EC2](dress-rehearse-ec2)** — prove a delivery on a bare host
   before the first client deploy.
7. **[Upgrades & revocation](upgrades-revocation)** — ship a new version, or revoke a
   client's access.
