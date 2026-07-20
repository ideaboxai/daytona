# Daytona — client install guide

You received a Daytona server deployment. This guide brings it up on your own
infrastructure. **No git clone or GitHub access is needed** — everything is in the
source archive you were given.

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

## Steps

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

## Notes

- Sandbox in-browser port previews need the HTTPS + wildcard-domain path; they do not
  work over a bare IP.
- The third-party images (dex, minio, otel-collector, registry, registry-ui, jaeger)
  pull from Docker Hub. The four Daytona **server** images come from the vendor
  registry — those are the AGPL artifact covered by your source archive.
