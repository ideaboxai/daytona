# Daytona on EC2 — single-node, HTTP, reuse prod Postgres/Redis (TESTING)

Deploys the four service images from ECR
(`304038454586.dkr.ecr.us-east-1.amazonaws.com/ideaboxai/daytona-*:hub-20260720`)
onto one EC2 box over plain HTTP. Not production — no TLS. Uses
`docker-compose.ec2-http.override.yaml`.

> **Scope:** dashboard, API, sandbox create/exec, and SSH work over the IP.
> In-browser sandbox **port previews do NOT** — they need wildcard subdomains,
> which can't resolve against a bare IP. That needs the HTTPS + domain path.

---

## ⚠ Two traps of reusing prod datastores — do these first

**1. Give Daytona its OWN Postgres database — never point at an app's existing DB.**
Daytona runs migrations on boot (`RUN_MIGRATIONS=true`) and will create/alter its
own tables. Sharing the *instance* is fine; sharing a *database* corrupts things.
On the prod Postgres:
```sql
CREATE DATABASE daytona;
CREATE USER daytona WITH PASSWORD '<pick-one>';
GRANT ALL PRIVILEGES ON DATABASE daytona TO daytona;
```
Then set `DB_DATABASE=daytona` and that user in `.env`.

**2. Redis: must be non-cluster, and Daytona uses logical DB 0.**
The proxy's client is standalone-only (no cluster support), and there is no
`REDIS_DB` setting — Daytona writes `runner:jobs:*`, `sandbox:activity`, and BullMQ
queues to **DB 0**. If a prod app shares DB 0, a `FLUSHDB` there wipes Daytona's
queues. Strongly prefer a dedicated Redis instance; at minimum confirm it's not
cluster-mode and know what else lives on DB 0.

**TLS to prod:** if prod Postgres requires TLS, set `DB_TLS_ENABLED=true` and drop
its CA at `docker/certs/rds-ca-bundle.pem` (the api mounts it). If not, set
`DB_TLS_ENABLED=false`. Same idea for `REDIS_TLS`.

---

## EC2 prerequisites (the runner is picky)

The `runner` runs privileged Docker-in-Docker. On the box, confirm:
- **`mount-s3` binary** at `/usr/bin/mount-s3` — the compose bind-mounts it into the
  runner; if absent, Docker silently mounts an empty dir and the runner misbehaves.
  Install [mountpoint-s3](https://github.com/awslabs/mountpoint-s3).
- **`/dev/fuse`** present (standard on AL2023 / Ubuntu; absent on minimal AMIs).
- **ECR pull access** — either an instance role with `ecr:GetAuthorizationToken`,
  `BatchGetImage`, `GetDownloadUrlForLayer`, or `docker login` (step 3).
- **Security group inbound:** `3002` (api/dashboard), `4003` (proxy), `5556` (dex),
  `2222` (ssh-gateway). Others bind to 127.0.0.1.

The 6 third-party images (dex, minio, otel-collector, registry, registry-ui,
jaeger) pull from **Docker Hub** — they were not mirrored to this account. Fine for
a test; mirror them later for full Hub independence.

---

## Steps (on the EC2)

**1. Get the repo's `docker/` dir on the box** (git clone, or scp just `docker/`).

**2. Fill `docker/.env`** — copy from `.env.example`, then add:
```bash
FORK_REGISTRY=304038454586.dkr.ecr.us-east-1.amazonaws.com/ideaboxai
FORK_TAG=hub-20260720
EC2_HOST=<this box's public IP or DNS>     # no scheme, no port
DB_HOST=<prod-postgres-host>
DB_USERNAME=daytona
DB_PASSWORD=<the password you set above>
DB_DATABASE=daytona
DB_TLS_ENABLED=true            # false if prod pg has no TLS
REDIS_HOST=<prod-redis-host>
REDIS_PASSWORD=<or empty>
REDIS_TLS=true                 # false if prod redis has no TLS
SSH_GATEWAY_HOST=<this box's public IP>
```
Plus all the existing secrets (`ENCRYPTION_KEY`, tokens, SSH keys, etc.).

**3. Log in to ECR:**
```bash
aws ecr get-login-password --region us-east-1 \
  | docker login --username AWS --password-stdin \
    304038454586.dkr.ecr.us-east-1.amazonaws.com
```

**4. Generate the IP-based dex config** (gitignored):
```bash
cd <repo root>
EC2_HOST=<this box's public IP>
sed -e "s#https://sandbox.ideaboxai.com/dex#http://$EC2_HOST:5556/dex#g" \
    -e "s#https://proxy.sandbox.ideaboxai.com#http://$EC2_HOST:4003#g" \
    -e "s#https://sandbox.ideaboxai.com#http://$EC2_HOST:3002#g" \
    docker/dex/config.yaml > docker/dex/config.ec2.yaml
```

**5. Bring it up** (override applied LAST):
```bash
docker compose --env-file docker/.env \
  -f docker/docker-compose.yaml \
  -f docker/docker-compose.ec2-http.override.yaml up -d
```

**6. Watch it come up:**
```bash
docker compose --env-file docker/.env \
  -f docker/docker-compose.yaml -f docker/docker-compose.ec2-http.override.yaml \
  logs -f api
```
Wait for: `🚀 Daytona API is running on: http://0.0.0.0:3002/api`. The api needs
dex, minio, otel-collector, and a healthy runner all up — if it crash-loops, the
log names the missing one.

**7. Open the dashboard:** `http://<EC2_HOST>:3002/dashboard`
Login: `dev@daytona.io` / `password` (from dex `staticPasswords`).

---

## If the dashboard login misbehaves

IP-based OIDC is the fiddly part. Login redirects browser → dex
(`http://<EC2_HOST>:5556/dex`) → back to the dashboard. If it loops or errors:
- Confirm port `5556` is open in the security group.
- Confirm `docker/dex/config.ec2.yaml` issuer and every redirect URI use the real
  `EC2_HOST` (not `sandbox.ideaboxai.com`, not `10.0.0.5`).
- Confirm `PUBLIC_OIDC_DOMAIN` (api) and `OIDC_PUBLIC_DOMAIN` (proxy) both point at
  `http://<EC2_HOST>:5556/dex` (they do, via the override).
