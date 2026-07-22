#!/usr/bin/env bash
#
# Copyright 2025 Daytona Platforms Inc.
# SPDX-License-Identifier: AGPL-3.0
#
# Seed the client's OWN internal registry with all 11 Daytona images from the
# offline bundle (10 compose images + the daytona-sandbox default snapshot). Run
# ONCE, on a host that has the bundle AND can reach the internal registry. Afterwards
# every node pulls all 11 images from that registry — no Docker Hub, no vendor ECR at
# deploy. (The default snapshot is additionally relayed into each node's on-box
# registry:6000 by install.sh, which is where the runner pulls it from.)
#
# Reads IMAGES.txt (shipped in the bundle), loads images.tar, retags each image to
# <registry-prefix>/<leaf>, and pushes. The leaf paths match exactly what the
# compose overrides expect (ec2-http for the 4 server images, registry override for
# the 6 third-party), so deploy needs only FORK_REGISTRY=<prefix>.
#
# Prereqs: `docker login <registry-host>` first if the registry needs auth; the
# registry must accept these repositories (some registries require repos precreated).
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE"

[ -f IMAGES.txt ] || { echo "!! IMAGES.txt not found — run this inside the extracted bundle." >&2; exit 1; }

ask() { local v; read -rp "$1${2:+ [$2]}: " v; printf '%s' "${v:-$2}"; }

echo "== Seed internal registry with Daytona images =="
REGISTRY="$(ask 'Internal registry host (host[:port])' '')"
[ -n "$REGISTRY" ] || { echo "!! registry host required" >&2; exit 1; }
NAMESPACE="$(ask 'Namespace/path under the registry (blank for none)' 'daytona')"
PREFIX="$REGISTRY${NAMESPACE:+/$NAMESPACE}"

# --- load the offline images once -----------------------------------------
if [ -f images.tar ]; then
  echo ">> Loading images from images.tar (offline)…"
  docker load -i images.tar
else
  echo ">> images.tar not present — assuming the 11 images are already loaded locally."
fi

# --- retag + push each image to <PREFIX>/<leaf> ---------------------------
# leaf names MUST match docker-compose.registry.override.yaml AND the repo names
# mirror-thirdparty.sh uses (and the ECR repos DevOps created):
#   ours          -> basename                 e.g. daytona-api:<tag>
#   third-party   -> canonical ECR repo name  e.g. dexidp/dex -> dex, minio/minio -> minio
# The mapping is deliberately irregular (jaeger keeps its org, others drop theirs) —
# keep it in lockstep with mirror-thirdparty.sh.
canon() {
  local s="$1" name="${1%:*}" tag="${1##*:}"
  case "$name" in
    dexidp/dex)                           echo "dex:$tag" ;;
    joxit/docker-registry-ui)             echo "docker-registry-ui:$tag" ;;
    minio/minio)                          echo "minio:$tag" ;;
    otel/opentelemetry-collector-contrib) echo "opentelemetry-collector-contrib:$tag" ;;
    jaegertracing/all-in-one)             echo "jaegertracing/all-in-one:$tag" ;;
    registry)                             echo "registry:$tag" ;;
    *)                                    echo "${s##*/}" ;;   # ours: basename
  esac
}

echo ">> Retagging + pushing to $PREFIX"
FORK_TAG=""
while IFS= read -r src; do
  [ -n "$src" ] || continue
  leaf="$(canon "$src")"
  case "$src" in */daytona-*) FORK_TAG="${leaf##*:}" ;; esac   # remember the server tag
  dst="${PREFIX}/${leaf}"
  echo "   $src  ->  $dst"
  docker tag "$src" "$dst"
  docker push "$dst"
done < IMAGES.txt

echo
echo ">> Done. All images pushed under: $PREFIX"
echo ">> Deploy config — set these in docker/.env (or answer them to install.sh):"
echo "     FORK_REGISTRY=$PREFIX"
echo "     FORK_TAG=$FORK_TAG"
echo ">> Then bring up pulling ALL images from your registry:"
echo "     IMAGE_SOURCE=registry FORK_REGISTRY=$PREFIX ./install.sh"
echo "   (or manually add -f docker/docker-compose.registry.override.yaml)"
