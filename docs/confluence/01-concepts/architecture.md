---
title: Architecture
labels: [byoc, explanation]
---

> Source: generated from `docs/confluence/01-concepts/architecture.md`. Edit in git, not in Confluence.

# Architecture

A Daytona sandbox deployment is a single Docker Compose stack of **ten services**
plus the client's **own external Postgres and Redis**. Every delivery scenario ships
the same compose, dex config, and boot chain — only the [image source](registries-provenance)
differs. This page explains what each piece does and the one constraint that shapes
the whole deployment.

## The ten services

Source: `docker/docker-compose.yaml`.

| Service | Image | Published port | What it does |
|---|---|---|---|
| **api** | `daytonaio/daytona-api` | `3002` | Main Daytona application server. Runs TypeORM migrations on boot (`RUN_MIGRATIONS=true`), so it needs its own database. |
| **proxy** | `daytonaio/daytona-proxy` | `4003` | Request proxy; serves sandbox preview URLs. Uses Redis as a standalone client. |
| **runner** | `daytonaio/daytona-runner` | `3003` | Hosts the Daytona Runner. **Privileged Docker-in-Docker** — runs an inner dockerd that launches the sandbox containers (see below). |
| **ssh-gateway** | `daytonaio/daytona-ssh-gateway` | `2222` | Handles sandbox SSH access. |
| **dex** | `dexidp/dex:v2.42.0` | `5556` | OIDC authentication provider. |
| **registry-ui** | `joxit/docker-registry-ui:main` | `127.0.0.1:5100` | Web UI for the in-stack registry. |
| **registry** | `registry:2.8.2` | `127.0.0.1:6000` | In-stack Docker image registry — the api's internal/transient registry for sandbox snapshots (`registry:6000`). Not to be confused with the ECR that holds the ten delivery images. |
| **minio** | `minio/minio:latest` | `127.0.0.1:9001` (console) | S3-compatible object storage; console on `9001`, S3 API on `9000` in-network. |
| **jaeger** | `jaegertracing/all-in-one:1.67.0` | `127.0.0.1:16686` | Distributed tracing UI. In-memory span store (`SPAN_STORAGE_TYPE=memory`) — traces are a live debugging aid, not durable state. |
| **otel-collector** | `otel/opentelemetry-collector-contrib:0.138.0` | *(none published)* | Receives OTLP from the api (`http://otel-collector:4318`) and fans traces to jaeger. |

All services share the `daytona-network` bridge. `registry-ui`, `registry`, `minio`,
and `jaeger` bind only to `127.0.0.1` (local-only); the four **inbound** public ports
are `3002` (api/dashboard), `4003` (proxy), `5556` (dex), and `2222` (ssh-gateway).

## The privileged runner is the deciding constraint

The `runner` is the reason this stays a Docker Compose deployment rather than
Kubernetes. It runs the sandbox workloads as **Docker-in-Docker**: an inner Docker
daemon inside the runner container starts each sandbox as a container. To do that,
its compose definition requires:

- `privileged: true`
- `cap_add: [SYS_ADMIN]`
- `security_opt: [apparmor:unconfined]`
- the host device `/dev/fuse` (`devices: /dev/fuse:/dev/fuse`)
- a read-only bind-mount of the host binary `/usr/bin/mount-s3`
  (`volumes: /usr/bin/mount-s3:/usr/bin/mount-s3:ro`)
- an inline `/etc/docker/daemon.json` for the inner dockerd that trusts the in-stack
  registry (`"insecure-registries": ["registry:6000"]`) and bounds sandbox log growth

That combination — a privileged, host-device-dependent DinD workload bind-mounting a
host binary — is what keeps the deployment on a **single-host Docker Compose stack**.
It maps cleanly to one host with those devices present; it is exactly the kind of
workload that does not port cleanly to Kubernetes. (Related: sandbox resource limits
are disabled because cgroups cannot be partitioned in this DinD setup where the sock
is not mounted.)

## External Postgres and Redis

Postgres and Redis are **not** in the stack — they are the client's managed services
(RDS / ElastiCache), with endpoints set in `docker/.env`. The removed in-stack `db`
and `redis` containers (and the dev-only pgAdmin / MailDev) are gone. Two constraints
are enforced by the code, not by preference:

- **Daytona needs its own database.** The api runs migrations on boot, so sharing a
  Postgres *instance* is fine but sharing a *database* is not.
- **Redis must be non-cluster, DB 0 only.** The proxy uses a standalone go-redis
  client and the api uses BullMQ; there is no `REDIS_DB` setting, so a co-tenant app
  issuing `FLUSHDB` on DB 0 would drop Daytona's job queues. Prefer a dedicated
  instance.

RDS TLS note: RDS serves a cert from Amazon's private RDS CA that Node does not trust
by default. The api mounts a CA bundle at `docker/certs/rds-ca-bundle.pem` and points
`NODE_EXTRA_CA_CERTS` at it; without it, boot fails with `SELF_SIGNED_CERT_IN_CHAIN`.

## Host prerequisites and ports

The runner's DinD model dictates the host requirements:

- **`mount-s3`** at `/usr/bin/mount-s3` ([mountpoint-s3](https://github.com/awslabs/mountpoint-s3)) —
  the runner bind-mounts it; if it is missing the runner fails silently.
- **`/dev/fuse`** present on the host.
- **Docker** + the **compose** plugin.

Inbound ports to open: `3002` (api/dashboard), `4003` (proxy), `5556` (dex), `2222`
(ssh-gateway). TLS is terminated by an **external** load balancer / reverse proxy —
no proxy runs in the stack; containers speak plain HTTP and the external proxy must
forward `X-Forwarded-Proto: https`. Sandbox in-browser port previews need the HTTPS +
wildcard-subdomain path and do not work over a bare IP.

## Boot chain

The api will not come up alone: it needs Postgres, Redis, **dex**, **minio**,
**otel-collector**, and a healthy **runner** at boot. If it crash-loops, its log names
the missing dependency (`ENOTFOUND <service>` / connection refused). Success looks
like `🚀 Daytona API is running`. Booting is necessary but not sufficient — the real
acceptance signal is creating a sandbox, which exercises runner + proxy + ssh-gateway
together.

---

See **[Registries & image provenance](registries-provenance)** for where these ten
images come from, and **[Delivery scenarios](../02-delivery-scenarios)** for how they
reach a client's host.
