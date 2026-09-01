#!/usr/bin/env bash
#
# Copyright 2025 Daytona Platforms Inc.
# SPDX-License-Identifier: AGPL-3.0
#
# Assemble a single OFFLINE, air-gap BYOC delivery bundle for a client:
#   - all 11 images saved to images.tar (4 from-source + 6 third-party + 1 sandbox
#     snapshot); the sandbox snapshot must be built first (scripts/fork/build-sandbox.sh)
#     and tagged ${FORK_REGISTRY}/daytona-sandbox:${SNAPSHOT_TAG} — packing fails loudly
#     if it is absent.
#
# FORK_REGISTRY here is the CLIENT-facing RELEASE namespace (e.g.
# …/ideaboxai-release/<client>) that the client pulls from — the value promote.sh
# copies into. Not the build store (…/ideaboxai-platform-core).
#   - the compose files + dex/otel config + .env.example
#   - an interactive install.sh (loads images, prompts minimal config, brings up)
#   - the AGPL Corresponding-Source archive + WRITTEN_OFFER + sha256
# Produces one tarball the client untars and runs `./install.sh`.
#
# Run AFTER scripts/fork/byoc-release.sh (which builds the from-source images and
# writes the source archive + offer under dist/byoc/<client>/...). The from-source
# images must be pullable or already present locally.
#
# ARCHITECTURE: `docker save` captures the LOCAL platform only. Run on / pull for
# the client's arch (default amd64). For a mixed fleet, run once per arch.
#
# Usage:
#   CLIENT=actian \
#   FORK_REGISTRY=120354378950.dkr.ecr.us-east-1.amazonaws.com/ideaboxai-platform-core \
#   FORK_TAG=byoc-actian-20260720-79cb1970f \
#   BYOC_DIR=dist/byoc/actian/20260720-79cb1970f \
#     ./scripts/fork/byoc-bundle.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT"

CLIENT="${CLIENT:?Set CLIENT (lowercase slug), e.g. actian}"
FORK_REGISTRY="${FORK_REGISTRY:?Set FORK_REGISTRY (host + namespace of the from-source images)}"
FORK_TAG="${FORK_TAG:?Set FORK_TAG, e.g. byoc-actian-20260720-79cb1970f}"
BYOC_DIR="${BYOC_DIR:?Set BYOC_DIR — where byoc-release.sh wrote the source archive + offer}"
PLATFORM="${PLATFORM:-linux/amd64}"
# Copilot sandbox snapshot: friendly name the platform references (DAYTONA_SNAPSHOT_ID)
# and the version tag of the published image. Overridable at pack time.
SNAPSHOT_TAG="${SNAPSHOT_TAG:-1.1.0}"
SNAPSHOT_NAME="daytona-sandbox-v${SNAPSHOT_TAG}"
SNAPSHOT_IMAGE="${FORK_REGISTRY}/daytona-sandbox:${SNAPSHOT_TAG}"

[ -d "$BYOC_DIR" ] || { echo "!! BYOC_DIR '$BYOC_DIR' not found — run byoc-release.sh first." >&2; exit 1; }

# Our 4 from-source service images.
OURS=(api proxy runner ssh-gateway)
# Third-party images — KEEP IN SYNC with docker/docker-compose.yaml.
THIRD_PARTY=(
  dexidp/dex:v2.42.0
  joxit/docker-registry-ui:main
  registry:2.8.2
  jaegertracing/all-in-one:1.67.0
  minio/minio:latest
  otel/opentelemetry-collector-contrib:0.138.0
)

IMAGES=()
for svc in "${OURS[@]}"; do IMAGES+=("${FORK_REGISTRY}/daytona-${svc}:${FORK_TAG}"); done
IMAGES+=("${THIRD_PARTY[@]}")
# 11th image: the copilot sandbox snapshot, pulled + registered on first boot.
IMAGES+=("$SNAPSHOT_IMAGE")

STAGE_PARENT="$(mktemp -d)"
NAME="daytona-${CLIENT}-${FORK_TAG}"
STAGE="${STAGE_PARENT}/${NAME}"
mkdir -p "$STAGE/docker"

echo ">> Ensuring images are present locally (platform: $PLATFORM)"
for img in "${IMAGES[@]}"; do
  docker image inspect "$img" >/dev/null 2>&1 || docker pull --platform "$PLATFORM" "$img"
done

echo ">> Saving ${#IMAGES[@]} images -> images.tar (this is the big step)"
docker save "${IMAGES[@]}" -o "$STAGE/images.tar"
printf '%s\n' "${IMAGES[@]}" > "$STAGE/IMAGES.txt"

echo ">> Copying compose + configs"
cp docker/docker-compose.yaml \
   docker/docker-compose.ec2-http.override.yaml \
   docker/docker-compose.hardening.override.yaml \
   docker/docker-compose.registry.override.yaml \
   docker/.env.example \
   docker/CLIENT-INSTALL.md \
   "$STAGE/docker/"
cp -r docker/dex docker/otel "$STAGE/docker/"

# Postgres CA bundle — the api mounts docker/certs/rds-ca-bundle.pem for TLS.
# Ship it so RDS+TLS works air-gapped (no fetch at deploy). Prefer a repo-provided
# cert; else fetch Amazon's all-region RDS global bundle now (internet at pack time).
mkdir -p "$STAGE/docker/certs"
if [ -f docker/certs/rds-ca-bundle.pem ]; then
  cp docker/certs/rds-ca-bundle.pem "$STAGE/docker/certs/"
elif curl -fsSL https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem \
       -o "$STAGE/docker/certs/rds-ca-bundle.pem"; then
  echo "   shipped Amazon RDS global CA bundle"
else
  echo "!! could not obtain an RDS CA bundle; shipping empty placeholder."
  echo "   Clients on RDS+TLS must supply docker/certs/rds-ca-bundle.pem themselves."
  : > "$STAGE/docker/certs/rds-ca-bundle.pem"
fi

echo ">> Rendering install.sh + shipping seed-registry.sh"
sed -e "s|__FORK_REGISTRY__|${FORK_REGISTRY}|g" \
    -e "s|__FORK_TAG__|${FORK_TAG}|g" \
    -e "s|__SNAPSHOT_NAME__|${SNAPSHOT_NAME}|g" \
    -e "s|__SNAPSHOT_TAG__|${SNAPSHOT_TAG}|g" \
    scripts/fork/templates/install.sh > "$STAGE/install.sh"
chmod +x "$STAGE/install.sh"
# For clients who mirror into their own registry (e.g. air-gapped with an internal
# registry): seed-registry.sh loads images.tar and pushes all 11 to their registry.
cp scripts/fork/templates/seed-registry.sh "$STAGE/seed-registry.sh"
chmod +x "$STAGE/seed-registry.sh"

echo ">> Including AGPL Corresponding Source + written offer"
cp "$BYOC_DIR"/daytona-src-*.tar.gz "$BYOC_DIR"/daytona-src-*.tar.gz.sha256 \
   "$BYOC_DIR"/WRITTEN_OFFER.txt "$STAGE/"

# Small top-level readme so the client knows the entrypoint.
cat > "$STAGE/README.txt" <<EOF
Daytona — offline install bundle for ${CLIENT}
Image tag: ${FORK_TAG}   Platform: ${PLATFORM}

1. Extract this archive on your host (Docker + compose plugin required;
   see docker/CLIENT-INSTALL.md for host prerequisites incl. mount-s3/fuse).
2. Run:   ./install.sh
   It loads the images, asks for your Postgres/Redis endpoints and host
   address, generates all secrets, and starts the stack.

Have an internal registry / multiple nodes? Seed it once instead:
   ./seed-registry.sh    # pushes all 11 images to your registry
   IMAGE_SOURCE=registry FORK_REGISTRY=<prefix> ./install.sh   # on each node
See docker/CLIENT-INSTALL.md ("Deploy via your own internal registry").

WRITTEN_OFFER.txt + daytona-src-*.tar.gz are the AGPL-3.0 Corresponding Source
for the Daytona server in this bundle. Keep them.
EOF

OUT_DIR="dist/byoc/${CLIENT}"
mkdir -p "$OUT_DIR"
OUT="${OUT_DIR}/${NAME}.bundle.tar.gz"
echo ">> Packing $OUT"
tar czf "$OUT" -C "$STAGE_PARENT" "$NAME"
( cd "$OUT_DIR" && sha256sum "$(basename "$OUT")" > "$(basename "$OUT").sha256" )
rm -rf "$STAGE_PARENT"

SIZE="$(du -h "$OUT" | cut -f1)"
echo
echo ">> Bundle ready: $OUT  ($SIZE)"
echo ">> Deliver it + tell the client: extract, run ./install.sh"
