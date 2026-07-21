---
title: Prerequisites & ports
labels: [byoc, reference]
---

> Source: generated from `docs/confluence/05-reference/prerequisites-ports.md`. Edit in git, not in Confluence.

# Prerequisites & ports

Ported from `docker/CLIENT-INSTALL.md` and `docker/docker-compose.yaml`.

## Host prerequisites

| Requirement | Detail |
|---|---|
| Linux host | e.g. EC2. |
| **Docker** + the **compose** plugin | Container runtime and `docker compose`. On Ubuntu: `docker.io` + `docker-compose-plugin`. |
| `/usr/bin/mount-s3` | The `runner` bind-mounts `/usr/bin/mount-s3:/usr/bin/mount-s3:ro`. Without it the runner misbehaves silently. Install [mountpoint-s3](https://github.com/awslabs/mountpoint-s3). |
| `/dev/fuse` | The `runner` runs privileged Docker-in-Docker and needs the FUSE device (`/dev/fuse:/dev/fuse`). |
| **AWS CLI** | Configured with your account's credentials — used only to log in to the vendor registry (ECR pull is granted by the vendor). |

**Runner host note:** the `runner` runs privileged Docker-in-Docker. Both
`/usr/bin/mount-s3` (the `mount-s3` binary) and `/dev/fuse` must exist on the host
before the runner starts.

Bootstrap on a fresh Ubuntu VM:

```bash
sudo apt-get update
sudo apt-get install -y docker.io docker-compose-plugin awscli
sudo systemctl enable --now docker
sudo usermod -aG docker "$USER"      # then log out/in so docker works without sudo

# mount-s3: the runner bind-mounts /usr/bin/mount-s3
wget -q https://s3.amazonaws.com/mountpoint-s3-release/latest/x86_64/mount-s3.deb
sudo apt-get install -y ./mount-s3.deb
ls -l /usr/bin/mount-s3 /dev/fuse    # both must exist
```

## Inbound ports

Open these ports (inbound) on the host. These are the externally published service
ports from `docker/docker-compose.yaml`.

| Port | Service | Purpose |
|---|---|---|
| `3002` | api / dashboard | REST API and the web dashboard. |
| `4003` | proxy | Sandbox preview / proxy. |
| `5556` | dex | OIDC issuer (login). |
| `2222` | ssh-gateway | SSH into sandboxes. |

> Other published ports in the compose file (registry `6000`, registry-ui `5100`,
> minio console `9001`, jaeger UI `16686`) are bound to `127.0.0.1` only — they are
> not inbound and are not opened to the network.

## External Postgres & Redis constraints

Daytona does **not** ship its own database. You provide Postgres and Redis — managed
(RDS / ElastiCache) or containers you run — subject to two hard constraints:

- **Postgres — its own database.** Daytona runs TypeORM migrations on boot
  (`RUN_MIGRATIONS=true`), so it needs its **own** database. Sharing a Postgres
  *instance* is fine; sharing a *database* with another app is not. Never point it at
  an existing app's database. Create it first:

  ```sql
  CREATE DATABASE daytona;
  CREATE USER daytona WITH PASSWORD '...';
  GRANT ALL PRIVILEGES ON DATABASE daytona TO daytona;
  ```

- **Redis — non-cluster, DB 0.** Cluster mode is **NOT supported** (the Go proxy uses
  a standalone `*redis.Client` and the api uses BullMQ). Use a cluster-mode **DISABLED**
  instance (or its single primary endpoint). Daytona always uses logical **DB 0** —
  there is no `REDIS_DB` setting — and writes `runner:jobs:*`, `sandbox:activity`, and
  BullMQ queues there. Prefer a dedicated instance; a `FLUSHDB` from a co-tenant app
  would drop Daytona's job queues. Confirm with
  `redis-cli -h <host> INFO cluster` → `cluster_enabled:0`.

See **[Environment variables (.env)](environment-variables)** for the Postgres/Redis
connection variables and their TLS settings.
