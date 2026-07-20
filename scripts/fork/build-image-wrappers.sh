#!/usr/bin/env bash
#
# Copyright 2025 Daytona Platforms Inc.
# SPDX-License-Identifier: AGPL-3.0
#
# Build the four service images as THIN WRAPPERS over the upstream daytonaio/*
# images (docker/images/*.Dockerfile) and push them to OUR registry.
#
# This is a third path, between the other two:
#   - build-push.sh        builds from source (heaviest; provable commit for AGPL/BYOC)
#   - mirror-daytona-hub.sh straight-copies the prebuilt images (no hardening)
#   - THIS                  re-bases the prebuilt images + replays the non-root
#                           USER hardening (commit edda70ca8) WITHOUT a source build
#
# When to use it: you want the non-root runtime hardening but don't have (or don't
# want to wait on) the full Node/Go/Nx build toolchain. Not for shipping to BYOC
# clients — like the mirror, the exact upstream commit is not provable from here,
# and AGPL's Corresponding Source obligation wants that. Use build-push.sh there.
#
# MULTI-ARCH: upstream daytonaio/* are multi-arch manifest lists (amd64 + arm64).
# A plain `docker build FROM <multi-arch>` produces a SINGLE-arch image for the
# builder's platform, silently dropping the other arch. So this uses
# `docker buildx build --platform linux/amd64,linux/arm64 --push`, which rebuilds
# the wrapper for both arches off the corresponding base and pushes one combined
# manifest — the deploy target gets the right arch whether it's x86 or Graviton.
# The non-native leg runs the wrapper's one `adduser` under QEMU/binfmt; it is
# trivial, so emulation cost is negligible (unlike a from-source build).
#
# Requires a buildx builder with QEMU for the cross leg:
#   docker buildx create --use --name daytona-wrappers 2>/dev/null || true
#   docker run --privileged --rm tonistiigi/binfmt --install arm64
#
# Requires a docker login to the ECR *host* — not the namespace path:
#   aws ecr get-login-password --region us-east-1 \
#     | docker login --username AWS --password-stdin 120354378950.dkr.ecr.us-east-1.amazonaws.com
#
# Usage:
#   FORK_REGISTRY=120354378950.dkr.ecr.us-east-1.amazonaws.com/ideaboxai-platform-core \
#     ./scripts/fork/build-image-wrappers.sh
#
#   # single-arch (faster, no QEMU) — must match the deploy target:
#   PLATFORMS=linux/amd64 FORK_REGISTRY=... ./scripts/fork/build-image-wrappers.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT"

FORK_REGISTRY="${FORK_REGISTRY:?Set FORK_REGISTRY, e.g. 120354378950.dkr.ecr.us-east-1.amazonaws.com/ideaboxai-platform-core (must include the namespace path)}"
PLATFORMS="${PLATFORMS:-linux/amd64,linux/arm64}"
# Which upstream tag to re-base from. Upstream froze on 2026-06-11, so :latest is
# effectively the final image, but pin it explicitly for a reproducible build.
UPSTREAM_TAG="${UPSTREAM_TAG:-latest}"
SHORT_SHA="$(git rev-parse --short HEAD)"
DATE="$(date -u +%Y%m%d)"
# Distinct prefix from build-push.sh (fork-) and mirror (hub-) so the provenance
# of any image in the registry is obvious from its tag alone.
TAG="${TAG:-wrap-${DATE}-${SHORT_SHA}}"

SERVICES=(api proxy runner ssh-gateway)

# ECR never auto-creates repositories on push. Check up front.
if command -v aws >/dev/null 2>&1 && [[ "$FORK_REGISTRY" == *.dkr.ecr.*.amazonaws.com/* ]]; then
  REGION="$(sed -E 's/.*\.dkr\.ecr\.([^.]+)\.amazonaws\.com.*/\1/' <<<"$FORK_REGISTRY")"
  NAMESPACE="${FORK_REGISTRY#*/}"
  missing=()
  for svc in "${SERVICES[@]}"; do
    aws ecr describe-repositories --region "$REGION" \
      --repository-names "${NAMESPACE}/daytona-${svc}" >/dev/null 2>&1 \
      || missing+=("${NAMESPACE}/daytona-${svc}")
  done
  if (( ${#missing[@]} )); then
    echo "!! Missing ECR repositories in ${REGION}:" >&2
    printf '     %s\n' "${missing[@]}" >&2
    exit 1
  fi
  echo ">> Preflight OK: all ${#SERVICES[@]} ECR repositories exist in $REGION"
fi

DIGESTS_FILE="dist/fork-wrapper-digests-${TAG}.txt"
mkdir -p dist
{
  echo "# tag:          $TAG"
  echo "# platforms:    $PLATFORMS"
  echo "# upstream tag: $UPSTREAM_TAG"
  echo "# built by:     build-image-wrappers.sh (re-based + hardened, not from source)"
} > "$DIGESTS_FILE"

echo ">> Building wrappers (tag: $TAG, platforms: $PLATFORMS, base tag: $UPSTREAM_TAG)"
for svc in "${SERVICES[@]}"; do
  dst="${FORK_REGISTRY}/daytona-${svc}:${TAG}"
  echo ">> daytona-${svc}"
  # --provenance=false keeps the pushed artifact a plain manifest list rather than
  # an OCI image index with an attestation manifest, so the digest pins cleanly.
  docker buildx build \
    --platform "$PLATFORMS" \
    --build-arg "UPSTREAM_TAG=${UPSTREAM_TAG}" \
    --provenance=false \
    -f "docker/images/${svc}.Dockerfile" \
    -t "$dst" \
    --push \
    .

  digest="$(docker buildx imagetools inspect "$dst" --format '{{.Manifest.Digest}}')"
  echo "daytona-${svc} ${dst} ${FORK_REGISTRY}/daytona-${svc}@${digest}" | tee -a "$DIGESTS_FILE"
done

echo ">> Pushed. Digests written to $DIGESTS_FILE"
echo ">> Pin these into docker/docker-compose.registry.override.yaml"
