---
title: Connected — all 10 from the vendor registry
labels: [byoc, client, connected]
---

> Source: generated from `docs/confluence/04-client-guides/connected-all-from-registry.md`. Ported from `docker/CLIENT-INSTALL-CONNECTED.md`. Edit in git, not in Confluence.

# Connected — all 10 from the vendor registry

You received a Daytona server deployment for a host **with outbound internet**. This
guide brings it up by **pulling every image from the vendor's registry** — all 10
images from our ECR, **no Docker Hub at all**. Use this path when your host can reach
the vendor registry but **cannot** reach Docker Hub (locked-down networks): the vendor
mirrors the 6 third-party images into their registry alongside the 4 server images.

> If your host **can** reach Docker Hub, use
> [Connected — vendor registry + Docker Hub](connected-registry-plus-hub) (4 server
> images from ECR, 6 third-party from Docker Hub). If your host is **air-gapped** (no
> internet egress), use the [Air-gapped — offline bundle](airgapped-offline-bundle)
> path instead — that loads images from a tarball.

## What you received

1. **Pull access** to the four Daytona **server** images in the vendor's container
   registry — your AWS account has been granted ECR pull. You build nothing.
2. **The deploy files** (`docker/` + `install.sh`) — compose files, dex/otel config,
   `.env.example`.
3. **The source archive** (`daytona-src-*.tar.gz`) — the complete Corresponding
   Source of the exact server version, your right under AGPL-3.0.
4. **`WRITTEN_OFFER.txt`** — the AGPL-3.0 notice.
5. **These registry values** (given with your delivery):
   - registry host — e.g. `120354378950.dkr.ecr.us-east-1.amazonaws.com`
   - namespace — e.g. `ideaboxai-platform-core`
   - image tag — e.g. `fork-YYYYMMDD-<sha>`
   - region — e.g. `us-east-1`

## Prerequisites

- A Linux host (e.g. EC2) with **outbound internet**, **Docker**, and the **compose**
  plugin.
- **AWS CLI** configured with your account's credentials — used to log in to the
  vendor registry (the vendor granted your account pull access).
- **Postgres** and **Redis** you control (managed or self-run). Two hard constraints:
  - Daytona needs its **own** Postgres database (it runs migrations). Never point it
    at an existing app's database.
  - Redis must be **non-cluster**; Daytona uses logical **DB 0** (no `REDIS_DB`
    setting). Prefer a dedicated instance.
- **Runner host prereqs:** the `runner` runs privileged Docker-in-Docker. The host
  needs `/dev/fuse` and the `mount-s3` binary at `/usr/bin/mount-s3`
  ([mountpoint-s3](https://github.com/awslabs/mountpoint-s3)).
- **Open ports** (inbound): `3002` (api/dashboard), `4003` (proxy), `5556` (dex),
  `2222` (ssh-gateway).

### Bootstrap a fresh host (Ubuntu)

```bash
sudo apt-get update
sudo apt-get install -y docker.io docker-compose-plugin awscli
sudo systemctl enable --now docker
sudo usermod -aG docker "$USER"      # log out/in so docker works without sudo

# mount-s3: the runner bind-mounts /usr/bin/mount-s3 — without it the runner
# misbehaves silently
wget -q https://s3.amazonaws.com/mountpoint-s3-release/latest/x86_64/mount-s3.deb
sudo apt-get install -y ./mount-s3.deb
ls -l /usr/bin/mount-s3 /dev/fuse    # both must exist
```

## Quick install (recommended)

`install.sh` works for the connected path too — when there is **no `images.tar`**
beside it, it skips the offline load and expects the images to come from the
registry. So: log in to the registry, then run it with `IMAGE_SOURCE=registry`.

```bash
# 1. Log in to the vendor registry (your creds; pull is authorized by the vendor)
aws ecr get-login-password --region <REGION> \
  | docker login --username AWS --password-stdin <REGISTRY_HOST>

# 2a. ALL 10 images from the vendor registry — no Docker Hub at all. Use this if
#     your host can't reach Docker Hub (locked-down networks). The vendor mirrors
#     the 6 third-party images into their registry alongside the 4 server images.
IMAGE_SOURCE=registry ./install.sh
```

When prompted, use the vendor's registry host+namespace as the image source and this
host's address. After it starts, **pull happens on first `up`**. With `IMAGE_SOURCE=
registry`, install.sh adds the `registry` override so **all 10** resolve under your
`FORK_REGISTRY`. Then jump to **Verify**.

The manual steps below are for a bespoke setup (e.g. HTTPS behind your own domain) or
if you'd rather configure by hand.

## Manual install (alternative)

**1. Extract the source archive and enter it**
```bash
tar xzf daytona-src-<client>-<sha>.tar.gz
cd daytona-<sha>
```

**2. Log in to the vendor registry**
```bash
aws ecr get-login-password --region <REGION> \
  | docker login --username AWS --password-stdin <REGISTRY_HOST>
```

**3. Create Daytona's own database** on your Postgres:
```sql
CREATE DATABASE daytona;
CREATE USER daytona WITH PASSWORD '<pick-one>';
GRANT ALL PRIVILEGES ON DATABASE daytona TO daytona;
```
Confirm Redis is non-cluster: `redis-cli -h <host> INFO cluster` → `cluster_enabled:0`.

**4. Configure `docker/.env`**
```bash
cp docker/.env.example docker/.env
```
Set the image source (from your delivery), datastores, and host address:
```bash
FORK_REGISTRY=<REGISTRY_HOST>/<namespace>       # e.g. 120354378950.dkr.ecr.us-east-1.amazonaws.com/ideaboxai-platform-core
FORK_TAG=<the image tag provided>               # e.g. fork-YYYYMMDD-<sha>
EC2_HOST=<this host's public IP or DNS>

DB_HOST=<your-postgres-host>
DB_USERNAME=daytona
DB_PASSWORD=<from step 3>
DB_DATABASE=daytona
DB_TLS_ENABLED=true          # false if your Postgres has no TLS

REDIS_HOST=<your-redis-host>
REDIS_PASSWORD=<or empty>
REDIS_TLS=true               # false if your Redis has no TLS

SSH_GATEWAY_HOST=<this host's public IP>
```
Generate every remaining `CHANGEME` secret with `openssl rand -hex 32`, and the SSH
keys per the comments in the file. If your Postgres needs TLS, put its CA at
`docker/certs/rds-ca-bundle.pem`.

**5. Generate the IP-based dex config** (HTTP over the host IP):
```bash
EC2_HOST=<this host's public IP>
sed -e "s#https://sandbox.ideaboxai.com/dex#http://$EC2_HOST:5556/dex#g" \
    -e "s#https://proxy.sandbox.ideaboxai.com#http://$EC2_HOST:4003#g" \
    -e "s#https://sandbox.ideaboxai.com#http://$EC2_HOST:3002#g" \
    docker/dex/config.yaml > docker/dex/config.ec2.yaml
```
For **HTTPS behind your own domain + load balancer**: terminate TLS at your LB,
forward `X-Forwarded-Proto: https`, set the public URLs and the dex
`issuer`/`redirectURIs` to your domain, keep `PROXY_PROTOCOL=https`. See the
"Reverse proxy / TLS" section in `README.md`.

**6. Pull the images, then bring it up**

Add the `registry` override to pull **all 10** from the vendor registry (no Docker
Hub) — required if your host can't reach Docker Hub.
```bash
CF="--env-file docker/.env \
  -f docker/docker-compose.yaml \
  -f docker/docker-compose.ec2-http.override.yaml \
  -f docker/docker-compose.registry.override.yaml"     # omit for Docker-Hub third-party

docker compose $CF pull
docker compose $CF up -d
```
With the `registry` override, all 10 images resolve under your `FORK_REGISTRY` — the 4
`daytona-*` server images plus the 6 third-party the vendor mirrored (`dex`, `minio`,
`opentelemetry-collector-contrib`, `docker-registry-ui`, `jaegertracing/all-in-one`,
`registry`).

**7. Watch it come up**
```bash
docker compose --env-file docker/.env \
  -f docker/docker-compose.yaml \
  -f docker/docker-compose.ec2-http.override.yaml logs -f api
```
Wait for `🚀 Daytona API is running on: http://0.0.0.0:3002/api`. The api needs
Postgres, Redis, dex, minio, otel-collector, and a healthy runner — if it
crash-loops, the log names the missing one.

**8. Open the dashboard**

`http://<host>:3002/dashboard` (or your domain). Default login `dev@daytona.io` /
`password` — change it in `docker/dex/config.*.yaml` for anything beyond a first test.

## Verify (acceptance test)

Booting is necessary but not sufficient — confirm a sandbox actually works, since that
is what your application consumes. Follow the shared
**[Verify — acceptance test](../06-verify-operate/acceptance-test)**: check all
services are up, `curl http://<host>:3002/api/health` → `200`, then create a sandbox,
run a command in it, and delete it. A successful create + exec proves the runner
(Docker-in-Docker), proxy, and ssh-gateway all work — the real acceptance signal.

## Troubleshooting

- **`docker compose pull` denied / `no basic auth credentials`:** your `docker login`
  to the vendor registry expired or targeted the wrong host. Re-run the login in the
  Quick install step against `<REGISTRY_HOST>` (the host, not the namespace path).
- **`pull access denied` / `repository does not exist`:** the vendor hasn't granted
  your AWS account pull on that repo, or `FORK_REGISTRY`/`FORK_TAG` is wrong. Confirm
  the four values you were given and ask the vendor to verify the repository policy.
- **`api` crash-loops:** it needs Postgres, Redis, dex, minio, otel-collector, and a
  healthy runner at boot. `docker compose ... logs api` names the missing one.
- **`SELF_SIGNED_CERT_IN_CHAIN` on boot:** your Postgres TLS CA isn't trusted. Put its
  CA at `docker/certs/rds-ca-bundle.pem`, or set `DB_TLS_ENABLED=false`.
- **Sandbox create fails / hangs:** the runner host is missing `mount-s3` at
  `/usr/bin/mount-s3` or `/dev/fuse`. Install them and recreate the runner.

## Notes

- This is the **connected** path — it needs outbound internet at deploy to pull the
  vendor images (ECR). With the `registry` override, the third-party images come from
  the vendor's ECR too, so **no Docker Hub** is required. Air-gapped hosts must use the
  offline bundle path in [Air-gapped — offline bundle](airgapped-offline-bundle).
- Sandbox in-browser port previews need the HTTPS + wildcard-domain path; they do not
  work over a bare IP.
- The four Daytona **server** images are the AGPL artifact covered by your source
  archive; the third-party images are their vendors' own.
