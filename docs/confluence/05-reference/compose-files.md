---
title: Compose files & overrides
labels: [byoc, reference]
---

> Source: generated from `docs/confluence/05-reference/compose-files.md`. Edit in git, not in Confluence.

# Compose files & overrides

One base compose file plus four overrides. You compose them with repeated `-f` flags;
**later `-f` files win**, so ordering matters. All files declare `name: daytona`.

## The files

| File | What it does | When to apply |
|---|---|---|
| `docker-compose.yaml` | Base stack. Defines all services, published ports, the internal registry/minio/otel config, and the 6 third-party image names+tags. Server images are named as Docker Hub `daytonaio/daytona-*`. | Always — first `-f`. |
| `docker-compose.ec2-http.override.yaml` | Repoints the 4 server images to `${FORK_REGISTRY}/daytona-*:${FORK_TAG}` and rewrites the public URLs to the EC2 host over **HTTP** (`PROXY_PROTOCOL=http`, `PUBLIC_OIDC_DOMAIN`, `DASHBOARD_URL`, `PROXY_DOMAIN`, `PROXY_TEMPLATE_URL`). Swaps the dex config to `config.ec2.yaml` (`volumes: !override`) and disables the dex healthcheck. **TESTING ONLY, no TLS.** Requires `FORK_REGISTRY`, `FORK_TAG`, `EC2_HOST` in `docker/.env` plus `docker/dex/config.ec2.yaml`. | HTTP/IP deploys — after the base. |
| `docker-compose.registry.override.yaml` | Repoints the **6 third-party** images to `${FORK_REGISTRY}/<repo>:<tag>` so all 10 images come from one registry — no Docker Hub at deploy. Seed the third-party images first with `scripts/fork/mirror-thirdparty.sh` (our ECR) or `seed-registry.sh` (client's own). | Single-registry / no-Docker-Hub deploys — apply **LAST**, after base + ec2-http. |
| `docker-compose.hardening.override.yaml` | Adds `security_opt: no-new-privileges:true` to every service **except** the runner (privileged DinD needs privilege escalation). | Whenever you want the runtime hardening — apply **LAST so it wins**. |
| `docker-compose.build.override.yaml` | Adds `build:` (context `../`, `apps/<svc>/Dockerfile`, per-service `target`) to the 4 server images so `docker compose build` builds them from source instead of pulling. Used by `scripts/fork/build-push.sh`. | Building the server images from source. |

> A `docker-compose.registry.override.yaml.example` also exists — the variant with
> pinned `@sha256` digests to copy from.

## `-f` order (canonical combinations)

**HTTP over the host IP (base + ec2-http):**

```bash
docker compose --env-file docker/.env \
  -f docker/docker-compose.yaml \
  -f docker/docker-compose.ec2-http.override.yaml up -d
```

**All 10 images from one registry (base + ec2-http + registry):**

```bash
docker compose --env-file docker/.env \
  -f docker/docker-compose.yaml \
  -f docker/docker-compose.ec2-http.override.yaml \
  -f docker/docker-compose.registry.override.yaml pull
```

**With hardening applied last (base + registry + hardening):**

```bash
docker compose --env-file docker/.env \
  -f docker/docker-compose.yaml \
  -f docker/docker-compose.registry.override.yaml \
  -f docker/docker-compose.hardening.override.yaml up -d
```

**Build the server images from source (base + build):**

```bash
docker compose --env-file docker/.env \
  -f docker/docker-compose.yaml \
  -f docker/docker-compose.build.override.yaml
```

Use the **same `-f` file set** for follow-up commands (`ps`, `logs -f <service>`,
`restart`, `down`) as you used to bring the stack up.

See **[Image list & tags](image-list)** for what each override repoints, and
**[Environment variables (.env)](environment-variables)** for `FORK_REGISTRY`,
`FORK_TAG`, and `EC2_HOST`.
