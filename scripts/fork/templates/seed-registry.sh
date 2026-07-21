#!/usr/bin/env bash
#
# Copyright 2025 Daytona Platforms Inc.
# SPDX-License-Identifier: AGPL-3.0
#
# Seed the client's OWN internal registry with all 10 Daytona images from the
# offline bundle. Run ONCE, on a host that has the bundle AND can reach the
# internal registry. Afterwards every node pulls all 10 images from that registry —
# no Docker Hub, no vendor ECR at deploy.
#
# Reads IMAGES.txt (shipped in the bundle), loads images.tar, retags each image to
# <registry-prefix>/<leaf>, and pushes. The leaf paths match exactly what the
# compose overrides expect (ec2-http for the 4 server images, internal-registry for
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
  echo ">> images.tar not present — assuming the 10 images are already loaded locally."
fi

# --- retag + push each image to <PREFIX>/<leaf> ---------------------------
# leaf rule:
#   ours (source has a registry host + path)  -> basename           e.g. daytona-api:tag
#   third-party (Docker Hub name, no host)     -> keep the full name  e.g. dexidp/dex:v2.42.0
echo ">> Retagging + pushing to $PREFIX"
FORK_TAG=""
while IFS= read -r src; do
  [ -n "$src" ] || continue
  first="${src%%/*}"
  if [[ "$src" == */* && ( "$first" == *.* || "$first" == *:* ) ]]; then
    leaf="${src##*/}"                       # ours: daytona-<svc>:<tag>
    FORK_TAG="${leaf##*:}"                   # remember the server-image tag
  else
    leaf="$src"                             # third-party: org/name:tag or name:tag
  fi
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
echo "   (or manually add -f docker/docker-compose.internal-registry.override.yaml)"
