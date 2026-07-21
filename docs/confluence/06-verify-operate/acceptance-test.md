---
title: Acceptance test (boot + sandbox)
labels: [byoc, client]
---

> Source: generated from `docs/confluence/06-verify-operate/acceptance-test.md`. Ported from the "Verify (acceptance test)" section of `docker/CLIENT-INSTALL.md` and §5e of `BYOC-DELIVERY.md`. Edit in git, not in Confluence.

# Acceptance test (boot + sandbox)

Booting is necessary but not sufficient — confirm a sandbox actually works, since that is
what your application consumes. A successful **create + exec** proves the runner
(Docker-in-Docker), proxy, and ssh-gateway all work on the delivered images — the real
acceptance signal.

## 1. All services up

```bash
docker compose --env-file docker/.env \
  -f docker/docker-compose.yaml \
  -f docker/docker-compose.ec2-http.override.yaml ps
```

`api`, `proxy`, `runner`, `ssh-gateway`, `dex`, `minio`, `otel-collector`, `registry`
should be running; `api` reachable.

> Wait for `🚀 Daytona API is running` in the api logs before testing. The api needs
> Postgres, Redis, dex, minio, otel-collector, and a healthy runner at boot — if it
> crash-loops, the log names the missing one (see
> **[Troubleshooting](../07-troubleshooting)**).

## 2. API health

```bash
curl http://<host>:3002/api/health
```

Expect `200`.

## 3. Create a sandbox, exec, delete

From the dashboard, or with the Daytona SDK/CLI pointed at this deployment:

```bash
DAYTONA_API_URL=http://<host>:3002/api
```

(API key from the dashboard.) Run a command in the sandbox, then delete it. A successful
create + exec proves the runner (Docker-in-Docker), proxy, and ssh-gateway all work on the
delivered images — the real acceptance signal.

### Alternative — runner-direct smoke test (no browser / no API key)

To exercise the runner in isolation from the api and dashboard OIDC login, hit the
runner's own API directly. The compose publishes the runner on port **3003**
(`3003:3003`, `API_PORT=3003`) and authenticates it with the **`DAYTONA_RUNNER_TOKEN`**
from `docker/.env`. `POST /sandboxes` creates a sandbox straight on the runner — same
create → started → destroy lifecycle, minus the api/dashboard. Verified end-to-end in the
EC2 rehearsal:

```bash
TOK=$(grep '^DAYTONA_RUNNER_TOKEN=' docker/.env | cut -d= -f2-)
# make the snapshot available to the runner's inner Docker-in-Docker
docker exec daytona-runner-1 docker pull -q daytonaio/sandbox:0.5.0-slim

# create → expect HTTP 201 {"daemonVersion":"..."}
curl -s -X POST http://localhost:3003/sandboxes -H "Authorization: Bearer $TOK" \
  -H 'Content-Type: application/json' \
  -d '{"id":"smoke","userId":"u","snapshot":"daytonaio/sandbox:0.5.0-slim","osUser":"daytona","cpuQuota":1,"gpuQuota":0,"memoryQuota":1,"storageQuota":2}'

# confirm it is running → {"state":"started",...}
curl -s http://localhost:3003/sandboxes/smoke -H "Authorization: Bearer $TOK"

# (optional) see the real container in the runner's inner dockerd
docker exec daytona-runner-1 docker ps --filter name=smoke

# clean up → HTTP 200
curl -s -X POST http://localhost:3003/sandboxes/smoke/destroy -H "Authorization: Bearer $TOK"
```

`state: started` + a container in the inner dockerd proves the privileged runner actually
launches sandboxes on the delivered image. The dashboard/SDK path above is the primary,
supported route; this is the fast headless check.

---

This is the same acceptance test every delivery scenario ends at — see the
**[client install guides](../04-client-guides)**. When it fails, go to
**[Troubleshooting](../07-troubleshooting)**.

> Sandbox in-browser port previews need the HTTPS + wildcard-domain path; they do **not**
> work over a bare IP. Everything else in this test does.
