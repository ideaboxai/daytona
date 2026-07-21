---
title: Environment variables (.env)
labels: [byoc, reference]
---

> Source: generated from `docs/confluence/05-reference/environment-variables.md`. Edit in git, not in Confluence.

# Environment variables (.env)

Every variable in `docker/.env.example` — the authoritative env reference. Copy the
template to `docker/.env` (gitignored, **never commit**) and fill in real values:

```bash
cp docker/.env.example docker/.env
```

Load with:

```bash
docker compose --env-file docker/.env -f docker/docker-compose.yaml up -d
```

The compose file references only `${VAR}` — no secrets live in it. Generate strong
random values; do not reuse the placeholders. Example values below are the exact
placeholders from `docker/.env.example`.

## Encryption (app-level secret encryption)

| Variable | For | Example / default |
|---|---|---|
| `ENCRYPTION_KEY` | App-level secret encryption key. Generate with `openssl rand -hex 32`. | `CHANGEME_hex32` |
| `ENCRYPTION_SALT` | App-level secret encryption salt. Generate with `openssl rand -hex 32`. | `CHANGEME_hex32` |

## Postgres (external / managed, e.g. RDS)

Daytona needs its **OWN** database — it runs TypeORM migrations on boot
(`RUN_MIGRATIONS=true`). Sharing a Postgres *instance* is fine; sharing a *database*
with another app is not.

| Variable | For | Example / default |
|---|---|---|
| `DB_HOST` | Postgres host. | `CHANGEME.xxxxxxxx.us-east-1.rds.amazonaws.com` |
| `DB_PORT` | Postgres port. | `5432` |
| `DB_USERNAME` | Postgres user. | `daytona` |
| `DB_PASSWORD` | Postgres password. | `CHANGEME` |
| `DB_DATABASE` | Database name (Daytona's own DB). | `daytona` |
| `DB_TLS_ENABLED` | TLS to Postgres. Keep `true` for RDS. Set `false` for non-RDS Postgres without TLS. | `true` |
| `DB_TLS_REJECT_UNAUTHORIZED` | Verify the server cert. **Never set `false` in production** — it accepts any cert and defeats the point of TLS. | `true` |

> The api pins verification to Amazon's RDS CA via `NODE_EXTRA_CA_CERTS`; the bundle is
> mounted from `docker/certs/rds-ca-bundle.pem`. Download it once:
>
> ```bash
> mkdir -p docker/certs && curl -fsSL \
>   https://truststore.pki.rds.amazonaws.com/us-east-1/us-east-1-bundle.pem \
>   -o docker/certs/rds-ca-bundle.pem
> ```

## Redis (external / managed, e.g. ElastiCache)

> ⚠ **Cluster mode is NOT supported.** The Go proxy uses go-redis `*redis.Client`
> (standalone, see `libs/common-go/pkg/cache/redis_cache.go`) and the api uses BullMQ,
> which needs hash-tag work to run on a cluster. Use a cluster-mode **DISABLED**
> instance (or its single primary endpoint).
>
> ⚠ **Daytona always uses logical DB 0** — there is no `REDIS_DB` setting. It writes
> `runner:jobs:*`, `sandbox:activity`, and BullMQ queues there. Prefer a dedicated
> instance; a `FLUSHDB` from a co-tenant app would drop Daytona's job queues.

| Variable | For | Example / default |
|---|---|---|
| `REDIS_HOST` | Redis host. | `CHANGEME.xxxxxx.ng.0001.use1.cache.amazonaws.com` |
| `REDIS_PORT` | Redis port. | `6379` |
| `REDIS_USERNAME` | Redis username (optional). | *(empty)* |
| `REDIS_PASSWORD` | Redis password (or empty). | `CHANGEME_or_empty` |
| `REDIS_TLS` | ElastiCache in-transit encryption. Its certs chain to a publicly trusted Amazon CA, so no extra CA bundle is needed (unlike RDS). | `true` |

## Internal container registry (self-hosted `registry:6000`)

Transient store for sandbox snapshots created at runtime. Separate concern from ECR,
which holds the platform images — **both are needed**.

| Variable | For | Example / default |
|---|---|---|
| `REGISTRY_ADMIN` | Internal registry admin user. | `admin` |
| `REGISTRY_PASSWORD` | Internal registry password. | `CHANGEME` |

## MinIO / S3 object storage

| Variable | For | Example / default |
|---|---|---|
| `MINIO_ROOT_USER` | MinIO root user / S3 access key. | `daytona` |
| `MINIO_ROOT_PASSWORD` | MinIO root password / S3 secret key. | `CHANGEME` |

## Service API keys / tokens

`openssl rand -hex 32` each; must match across services.

| Variable | For | Example / default |
|---|---|---|
| `PROXY_API_KEY` | Shared key between api and proxy. | `CHANGEME` |
| `DAYTONA_RUNNER_TOKEN` | Runner auth token. | `CHANGEME` |
| `SSH_GATEWAY_API_KEY` | ssh-gateway ↔ api key. | `CHANGEME` |
| `OTEL_COLLECTOR_API_KEY` | OTEL collector auth. | `CHANGEME` |
| `HEALTH_CHECK_API_KEY` | Health-check endpoint key. | `CHANGEME` |

## SMTP (optional)

Leave `SMTP_HOST` empty to disable email. The **only** email Daytona sends is the
organization invitation (`apps/api/src/email/services/email.service.ts`) — with it
empty, invitations are still created, you just hand over the link yourself. Signup
needs no email: `SKIP_USER_EMAIL_VERIFICATION=true` in the compose file. To enable,
point at a relay (e.g. `email-smtp.us-east-1.amazonaws.com` / SES).

| Variable | For | Example / default |
|---|---|---|
| `SMTP_HOST` | Relay host; empty disables email. | *(empty)* |
| `SMTP_PORT` | Relay port. | `587` |
| `SMTP_USER` | Relay username. | *(empty)* |
| `SMTP_PASSWORD` | Relay password. | *(empty)* |
| `SMTP_SECURE` | TLS mode for the relay. | *(empty)* |
| `SMTP_EMAIL_FROM` | From header for outbound mail. | `Daytona Team <no-reply@ideaboxai.com>` |

## SSH gateway keypair + host key (base64-encoded)

Generate:

```bash
ssh-keygen -t rsa -b 4096 -N '' -f gw && base64 -w0 gw.pub  # -> SSH_GATEWAY_PUBLIC_KEY
base64 -w0 gw                                               # -> SSH_PRIVATE_KEY
ssh-keygen -t rsa -b 4096 -N '' -f host && base64 -w0 host  # -> SSH_HOST_KEY
```

| Variable | For | Example / default |
|---|---|---|
| `SSH_GATEWAY_PUBLIC_KEY` | Gateway public key (base64). | `CHANGEME_base64` |
| `SSH_PRIVATE_KEY` | Gateway private key (base64). | `CHANGEME_base64` |
| `SSH_HOST_KEY` | Gateway host key (base64). | `CHANGEME_base64` |
| `SSH_GATEWAY_HOST` | Public host of the SSH gateway (EC2 public IP or DNS). | `1.2.3.4` |

## Fork image registry

Only needed with `docker-compose.registry.override.yaml` (both variables are commented
out in the template). `FORK_REGISTRY` must include the ECR **namespace path**, not just
the host — `build-push.sh` appends `/daytona-<svc>`, so this must resolve to the real
repos.

| Variable | For | Example / default |
|---|---|---|
| `FORK_REGISTRY` | ECR registry host + namespace path. | `120354378950.dkr.ecr.us-east-1.amazonaws.com/ideaboxai-platform-core` |
| `FORK_TAG` | Image tag to pull. | `fork-YYYYMMDD-<shortsha>` |

See **[Image list & tags](image-list)** for how `FORK_REGISTRY` and `FORK_TAG` combine
into image references, and **[Compose files & overrides](compose-files)** for when the
registry override applies.
