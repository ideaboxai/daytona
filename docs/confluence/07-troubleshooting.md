---
title: Troubleshooting
labels: [byoc, troubleshooting]
---

> Source: generated from `docs/confluence/07-troubleshooting.md`. Ported from the "Troubleshooting" table of `BYOC-DELIVERY.md` and the "Troubleshooting" section of `docker/CLIENT-INSTALL.md`. Edit in git, not in Confluence.

# Troubleshooting

The failures we actually hit, with symptom → cause → fix. Split by where they bite:
**deploy-time** (the client's host) and **build/release** (operator, cutting a release).

## Deploy-time (client host)

| Symptom | Cause | Fix |
|---|---|---|
| **`api` crash-loops** (`ENOTFOUND <service>` / connection refused in `docker compose ... logs api`) | An eager boot dependency is missing — the api needs Postgres, Redis, dex, minio, otel-collector, and a healthy runner at boot | Start the named dependency; the api needs all of them, then it proceeds |
| **`SELF_SIGNED_CERT_IN_CHAIN` on boot** | Your Postgres TLS CA isn't trusted | Mount the CA bundle at `docker/certs/rds-ca-bundle.pem`, or set `DB_TLS_ENABLED=false` if your Postgres has no TLS |
| **Dashboard login loops / errors (HTTP-IP mode)** | dex `issuer` / `redirectURIs` are not the real host | Confirm port `5556` is open and every URL in `docker/dex/config.ec2.yaml` uses your real host, matching `PUBLIC_OIDC_DOMAIN` |
| **Sandbox create hangs / fails** | The runner host is missing `mount-s3` at `/usr/bin/mount-s3` or `/dev/fuse` | Install mountpoint-s3, ensure `/dev/fuse`, and recreate the runner |
| **ECR pull denied / `403` at deploy** | The client AWS account was not granted pull on the vendor ECR repos, or `docker` is not logged in / is authed to the wrong account | Vendor adds the account to the ECR repository policy (all 10 repos for the no-Docker-Hub case, else the 4 `daytona-*`); client logs in first: `aws ecr get-login-password --region <VENDOR_REGION> \| docker login --username AWS --password-stdin <VENDOR_REGISTRY_HOST>` |

## Build / release-time (operator)

| Symptom | Cause | Fix |
|---|---|---|
| **`build-push` "Missing ECR repositories"** (they exist) | Authed to the wrong AWS account — `describe-repositories` queries the *caller's* account | `aws sts get-caller-identity`; auth to the registry's account before anything else |
| **`build-push` "working tree is dirty"** | Not on the tag / local edits | `git checkout byoc/<client>/<date>-<sha>` |
| **runner build: `undefined: Bitmap`** | computer-use native build missing X11/CGO libs | Fixed — `build-push` builds it via `hack/computer-use/Dockerfile` |
| **build: `failed to calculate checksum ... go.work.sum`** | `go.work.sum` not generated | Fixed — `build-push` generates it in a golang container |

---

See **[Verify & operate](06-verify-operate)** for the acceptance test these failures show
up against, and the **[client install guides](04-client-guides)** for the full deploy steps.
