---
title: Air-gapped — offline bundle
labels: [byoc, client, air-gapped]
---

> Source: generated from `docs/confluence/04-client-guides/airgapped-offline-bundle.md`. Ported from `docker/CLIENT-INSTALL.md`. Edit in git, not in Confluence.

# Air-gapped — offline bundle

You received a Daytona server deployment. This guide brings it up on your own
infrastructure. **No git clone or GitHub access is needed** — everything is in the
source archive you were given.

> This is the **air-gapped** path: images are loaded from the offline bundle
> (`images.tar`), nothing is pulled from the internet. If your host **has outbound
> internet** and pulls the server images from the vendor registry instead, use
> [Connected — all from the vendor registry](connected-all-from-registry) or
> [Connected — vendor registry + Docker Hub](connected-registry-plus-hub).
>
> If you run more than one node or your nodes pull only from an **internal registry**,
> seed it once instead — see [Air-gapped / fleet — your own internal registry](airgapped-internal-registry).

## What you received

1. **Pull access** to the four server images in the vendor's container registry
   (your AWS account has been granted ECR pull). You do not build anything.
2. **This source archive** — the complete Corresponding Source of the exact server
   version running (your right under AGPL-3.0). Extract it; the deploy files live
   under `docker/`.
3. **`WRITTEN_OFFER.txt`** — the AGPL-3.0 notice. Your rights to use, study, modify,
   and redistribute the Daytona **server** are covered there.

## Prerequisites

- A Linux host (e.g. EC2) with **Docker** + the **compose** plugin.
- **AWS CLI** configured with your account's credentials (used only to log in to the
  vendor registry — the vendor granted your account pull access).
- **Postgres** and **Redis** you control — managed (RDS/ElastiCache) or containers
  you run. Two hard constraints:
  - Daytona needs its **own** Postgres database (it runs migrations). Never point it
    at an existing app's database.
  - Redis must be **non-cluster**, and Daytona uses logical **DB 0** (no `REDIS_DB`
    setting). Prefer a dedicated instance.
- **Runner host prereqs:** the `runner` runs privileged Docker-in-Docker. The host
  needs `/dev/fuse` and the `mount-s3` binary at `/usr/bin/mount-s3`
  ([mountpoint-s3](https://github.com/awslabs/mountpoint-s3)).
- **Open ports** (inbound): `3002` (api/dashboard), `4003` (proxy), `5556` (dex),
  `2222` (ssh-gateway).

### Bootstrap a fresh host (Ubuntu)

If starting from an empty VM:
```bash
sudo apt-get update
sudo apt-get install -y docker.io docker-compose-plugin awscli
sudo systemctl enable --now docker
sudo usermod -aG docker "$USER"      # then log out/in so docker works without sudo

# mount-s3: the runner bind-mounts /usr/bin/mount-s3 — without it the runner
# misbehaves silently
wget -q https://s3.amazonaws.com/mountpoint-s3-release/latest/x86_64/mount-s3.deb
sudo apt-get install -y ./mount-s3.deb
ls -l /usr/bin/mount-s3 /dev/fuse    # both must exist
```

## Quick install (recommended)

The delivery bundle includes a one-command installer. From the extracted bundle:

```bash
./install.sh
```

It loads the offline images, asks for your Postgres/Redis endpoints and this host's
address, generates every secret for you, writes `docker/.env` and the dex config, and
brings the stack up. You only answer ~6 prompts. Then jump to **Verify** below.

The manual steps below are for a bespoke setup (e.g. HTTPS behind your own domain) or
if you'd rather configure by hand.

## Manual install (alternative)

**1. Extract the source archive and enter it**
```bash
tar xzf daytona-src-<client>-<sha>.tar.gz
cd daytona-<sha>
```

**2. Log in to the vendor registry** (your creds; pull is authorized by the vendor's
repository policy). The registry host and image tag were given to you:
```bash
aws ecr get-login-password --region <VENDOR_REGION> \
  | docker login --username AWS --password-stdin <VENDOR_REGISTRY_HOST>
```

**3. Create Daytona's own database** on your Postgres:
```sql
CREATE DATABASE daytona;
CREATE USER daytona WITH PASSWORD '<pick-one>';
GRANT ALL PRIVILEGES ON DATABASE daytona TO daytona;
```
And confirm Redis is non-cluster: `redis-cli -h <host> INFO cluster` → `cluster_enabled:0`.

**4. Configure `docker/.env`**
```bash
cp docker/.env.example docker/.env
```
Set the image source (values provided with your delivery), your datastores, and the
host address:
```bash
FORK_REGISTRY=<VENDOR_REGISTRY_HOST>/<namespace>
FORK_TAG=<the image tag provided, e.g. byoc-<client>-<date>-<sha>>
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

**5. Pick an access mode**

*HTTP over the host IP (fastest, no TLS)* — generate the IP-based dex config:
```bash
sed -e "s#https://sandbox.ideaboxai.com/dex#http://$EC2_HOST:5556/dex#g" \
    -e "s#https://proxy.sandbox.ideaboxai.com#http://$EC2_HOST:4003#g" \
    -e "s#https://sandbox.ideaboxai.com#http://$EC2_HOST:3002#g" \
    docker/dex/config.yaml > docker/dex/config.ec2.yaml
```
Bring up with the HTTP override:
```bash
docker compose --env-file docker/.env \
  -f docker/docker-compose.yaml \
  -f docker/docker-compose.ec2-http.override.yaml up -d
```

*HTTPS behind your own domain + load balancer (production)* — terminate TLS at your
LB and forward `X-Forwarded-Proto: https`. Set the public URLs (`PUBLIC_OIDC_DOMAIN`,
`DASHBOARD_URL`, `PROXY_DOMAIN`, etc.) and the dex `issuer`/`redirectURIs` to your
domain, keep `PROXY_PROTOCOL=https`. See the "Reverse proxy / TLS" section in
`docker/README.md` for the route table. Then bring up with just the base compose +
the image override you were given.

**6. Watch it come up**
```bash
docker compose --env-file docker/.env \
  -f docker/docker-compose.yaml \
  -f docker/docker-compose.ec2-http.override.yaml logs -f api
```
Wait for `🚀 Daytona API is running on: http://0.0.0.0:3002/api`. The api needs
Postgres, Redis, dex, minio, otel-collector, and a healthy runner — if it
crash-loops, the log names the missing one.

**7. Open the dashboard**

`http://<host>:3002/dashboard` (or your domain). Default login `dev@daytona.io` /
`password` — change it in `docker/dex/config.*.yaml` for anything beyond a first test.

## Verify (acceptance test)

Booting is necessary but not sufficient — confirm a sandbox actually works, since that
is what your application consumes. Follow the shared
**[Verify — acceptance test](../06-verify-operate/acceptance-test)**: check all
services are up, `curl http://<host>:3002/api/health` → `200`, then create a sandbox,
run a command in it, and delete it. A successful create + exec proves the runner
(Docker-in-Docker), proxy, and ssh-gateway all work on the delivered images — the real
acceptance signal.

## Troubleshooting

- **`api` crash-loops:** it needs Postgres, Redis, dex, minio, otel-collector, and a
  healthy runner at boot. `docker compose ... logs api` names the missing one
  (`ENOTFOUND <service>` / connection refused). Fix that dependency and it proceeds.
- **`SELF_SIGNED_CERT_IN_CHAIN` on boot:** your Postgres TLS CA isn't trusted. Put its
  CA bundle at `docker/certs/rds-ca-bundle.pem`, or set `DB_TLS_ENABLED=false` if your
  Postgres has no TLS.
- **Dashboard login loops/errors (HTTP-IP mode):** confirm port `5556` is open and
  every URL in `docker/dex/config.ec2.yaml` uses your real host (issuer +
  redirectURIs), matching `PUBLIC_OIDC_DOMAIN`.
- **Sandbox create fails / hangs:** the runner host is missing `mount-s3` at
  `/usr/bin/mount-s3` or `/dev/fuse`. Install them and recreate the runner.

## Notes

- Sandbox in-browser port previews need the HTTPS + wildcard-domain path; they do not
  work over a bare IP.
- The third-party images (dex, minio, otel-collector, registry, registry-ui, jaeger)
  pull from Docker Hub. The four Daytona **server** images come from the vendor
  registry — those are the AGPL artifact covered by your source archive.
