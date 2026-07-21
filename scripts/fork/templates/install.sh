#!/usr/bin/env bash
#
# Copyright 2025 Daytona Platforms Inc.
# SPDX-License-Identifier: AGPL-3.0
#
# Daytona installer — runs on the client's host, inside the delivered bundle.
# Loads the offline images, collects the few settings that can't be defaulted,
# generates all secrets, and brings the stack up. Air-gap native: nothing is
# pulled from the internet.
#
# __FORK_REGISTRY__ / __FORK_TAG__ are filled in by byoc-bundle.sh at pack time.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE"

# DRY_RUN=1 → do everything (load images, write .env, gen secrets, render dex)
# but validate the merged compose instead of starting it. For pre-delivery tests.
DRY_RUN="${DRY_RUN:-0}"

# IMAGE_SOURCE=bundle (default) loads images from images.tar (air-gap). =registry
# skips the load and pulls all 10 from the client's own registry (seed it first with
# seed-registry.sh); set FORK_REGISTRY to that registry's prefix.
IMAGE_SOURCE="${IMAGE_SOURCE:-bundle}"
FORK_REGISTRY="${FORK_REGISTRY:-__FORK_REGISTRY__}"
FORK_TAG="${FORK_TAG:-__FORK_TAG__}"
ENV="docker/.env"
COMPOSE=(docker compose --env-file "$ENV"
  -f docker/docker-compose.yaml
  -f docker/docker-compose.ec2-http.override.yaml)
# registry mode: also repoint the 6 third-party images to ${FORK_REGISTRY}, so all
# 10 come from one registry (our ECR for actian, or the client's own).
[ "$IMAGE_SOURCE" = registry ] && COMPOSE+=(-f docker/docker-compose.registry.override.yaml)

echo "== Daytona install =="

# --- 1. Images: load from the bundle, or pull from the client's registry ---
if [ "$IMAGE_SOURCE" = registry ]; then
  echo ">> IMAGE_SOURCE=registry — skipping offline load; compose pulls all 10 from"
  echo "   your registry (seed it first with ./seed-registry.sh)."
elif [ -f images.tar ]; then
  echo ">> Loading images from images.tar (offline)…"
  docker load -i images.tar
else
  echo "!! images.tar not found — expecting the images already in a reachable registry." >&2
fi

# --- 2. Collect the minimal config ----------------------------------------
[ -f "$ENV" ] || cp docker/.env.example "$ENV"
ask()  { local v; read -rp "$1 [${2}]: " v; printf '%s' "${v:-$2}"; }
asks() { local v; read -rsp "$1: " v; echo >&2; printf '%s' "$v"; }   # secret input

DEFAULT_HOST="$(hostname -I 2>/dev/null | awk '{print $1}')"
HOST="$(ask 'Public IP/DNS of this host' "$DEFAULT_HOST")"
if [ "$IMAGE_SOURCE" = registry ]; then
  case "$FORK_REGISTRY" in ""|__FORK_REGISTRY__)
    FORK_REGISTRY="$(ask 'Internal registry prefix (host[:port][/namespace])' '')" ;;
  esac
fi
DB_HOST="$(ask 'Postgres host' '')"
DB_USER="$(ask 'Postgres user' 'daytona')"
DB_PASS="$(asks 'Postgres password')"
DB_TLS="$(ask 'Postgres TLS (true/false)' 'true')"
REDIS_HOST="$(ask 'Redis host' '')"
REDIS_PASS="$(asks 'Redis password (blank if none)')"
REDIS_TLS="$(ask 'Redis TLS (true/false)' 'true')"

# --- 3. Write config + generate every secret ------------------------------
# Value passed via env so nothing needs shell escaping (base64 keys contain / + =).
set_env() {
  ENV="$ENV" K="$1" V="$2" python3 - <<'PY'
import os
p=os.environ["ENV"]; k=os.environ["K"]; v=os.environ["V"]
try: lines=open(p).read().splitlines()
except FileNotFoundError: lines=[]
out=[]; found=False
for l in lines:
    if l.startswith(k+"="): out.append(f"{k}={v}"); found=True
    else: out.append(l)
if not found: out.append(f"{k}={v}")
open(p,"w").write("\n".join(out)+"\n")
PY
}
gen() { openssl rand -hex 32; }
# regenerate if the key is missing or still an example placeholder
need() { ! grep -q "^$1=" "$ENV" || grep -qiE "^$1=(change|$)" "$ENV"; }

set_env FORK_REGISTRY "$FORK_REGISTRY"
set_env FORK_TAG      "$FORK_TAG"
set_env EC2_HOST      "$HOST"
set_env SSH_GATEWAY_HOST "$HOST"

set_env DB_HOST "$DB_HOST"; set_env DB_USERNAME "$DB_USER"; set_env DB_PASSWORD "$DB_PASS"
set_env DB_DATABASE daytona; set_env DB_TLS_ENABLED "$DB_TLS"
set_env REDIS_HOST "$REDIS_HOST"; set_env REDIS_PASSWORD "$REDIS_PASS"; set_env REDIS_TLS "$REDIS_TLS"

set_env REGISTRY_ADMIN admin
set_env MINIO_ROOT_USER daytona
for k in ENCRYPTION_KEY ENCRYPTION_SALT REGISTRY_PASSWORD MINIO_ROOT_PASSWORD \
         PROXY_API_KEY DAYTONA_RUNNER_TOKEN SSH_GATEWAY_API_KEY \
         OTEL_COLLECTOR_API_KEY HEALTH_CHECK_API_KEY; do
  need "$k" && set_env "$k" "$(gen)"
done

# SSH gateway keypair + host key (base64), generated once
if need SSH_PRIVATE_KEY; then
  TMP="$(mktemp -d)"
  ssh-keygen -q -t rsa -b 4096 -N '' -f "$TMP/gw"
  ssh-keygen -q -t rsa -b 4096 -N '' -f "$TMP/host"
  set_env SSH_GATEWAY_PUBLIC_KEY "$(base64 -w0 "$TMP/gw.pub")"
  set_env SSH_PRIVATE_KEY        "$(base64 -w0 "$TMP/gw")"
  set_env SSH_HOST_KEY           "$(base64 -w0 "$TMP/host")"
  rm -rf "$TMP"
fi
chmod 600 "$ENV"

# --- 4. dex config for this host ------------------------------------------
sed -e "s#https://sandbox.ideaboxai.com/dex#http://$HOST:5556/dex#g" \
    -e "s#https://proxy.sandbox.ideaboxai.com#http://$HOST:4003#g" \
    -e "s#https://sandbox.ideaboxai.com#http://$HOST:3002#g" \
    docker/dex/config.yaml > docker/dex/config.ec2.yaml

# --- 4b. Postgres CA bundle ------------------------------------------------
# The api bind-mounts docker/certs/rds-ca-bundle.pem (NODE_EXTRA_CA_CERTS). If the
# file is absent, Docker would mount an empty DIRECTORY there and Node ignores it.
# Guarantee it's a real file so the mount is valid; the bundle ships the RDS CA.
mkdir -p docker/certs
[ -f docker/certs/rds-ca-bundle.pem ] || : > docker/certs/rds-ca-bundle.pem
if [ "$DB_TLS" = "true" ] && [ ! -s docker/certs/rds-ca-bundle.pem ]; then
  echo "!! DB TLS is on but docker/certs/rds-ca-bundle.pem is empty."
  echo "   Put your Postgres CA there (for RDS it ships in this bundle), or answer"
  echo "   DB TLS = false. Continuing — the api will fail TLS verify until fixed."
fi

# --- 5. Preconditions the client must meet --------------------------------
cat <<EOF

Before continuing, confirm on your side:
  * Postgres '$DB_HOST' has a database 'daytona' owned by '$DB_USER':
      CREATE DATABASE daytona;
      CREATE USER $DB_USER WITH PASSWORD '…';
      GRANT ALL PRIVILEGES ON DATABASE daytona TO $DB_USER;
  * Redis '$REDIS_HOST' is non-cluster (INFO cluster -> cluster_enabled:0)
  * /usr/bin/mount-s3 and /dev/fuse exist on this host (the runner needs them)
EOF
if [ "$DRY_RUN" = "1" ]; then
  echo
  echo ">> DRY_RUN=1 — validating merged compose (not starting)…"
  "${COMPOSE[@]}" config -q && echo ">> compose config OK — .env + overrides resolve."
  echo ">> Dry run done. Re-run without DRY_RUN to bring the stack up."
  exit 0
fi

read -rp "Press Enter to bring the stack up (Ctrl-C to abort)…" _

# --- 6. Up ----------------------------------------------------------------
"${COMPOSE[@]}" up -d
echo
echo ">> Started. Watch the api boot:"
echo "   docker compose --env-file docker/.env -f docker/docker-compose.yaml \\"
echo "     -f docker/docker-compose.ec2-http.override.yaml logs -f api"
echo "   (wait for: 🚀 Daytona API is running)"
echo ">> Dashboard: http://$HOST:3002/dashboard   (dev@daytona.io / password)"
echo ">> Change that password in docker/dex/config.ec2.yaml before real use."
