#!/usr/bin/env bash
#
# Copyright 2025 Daytona Platforms Inc.
# SPDX-License-Identifier: AGPL-3.0
#
# Build the default sandbox base image (repo `daytona-sandbox`) and push it to OUR
# registry with a versioned tag. This is the image the runner turns into a sandbox;
# it is registered as the default snapshot on first boot (DEFAULT_SNAPSHOT_IMAGE).
#
# The image itself is the PLATFORM's application sandbox (python + data-science +
# playwright/node), NOT a Daytona AGPL artifact. By default it builds from the
# vendored copy at images/daytona-sandbox/. Set SNAPSHOT_SRC to a live checkout of
# the platform's snapshot_builder dir to build from the canonical Dockerfile.snapshot
# with no drift (records which source was used in the digest ledger).
#
# ARCHITECTURE: a plain `docker build` is single-arch (the builder's). TARGET_PLATFORM
# must match the deploy target — an amd64 image will not run on Graviton, and the
# failure only surfaces at deploy. Defaults to linux/amd64.
#
# Requires a docker login to the ECR *host* (not the namespace path):
#   aws ecr get-login-password --region us-east-1 \
#     | docker login --username AWS --password-stdin 120354378950.dkr.ecr.us-east-1.amazonaws.com
#
# Usage:
#   FORK_REGISTRY=120354378950.dkr.ecr.us-east-1.amazonaws.com/ideaboxai-platform-core \
#     ./scripts/fork/build-sandbox.sh
#
#   # Build from the live platform Dockerfile instead of the vendored copy:
#   SNAPSHOT_SRC=/path/to/ideaboxai-multi-agent-service/scripts/snapshot_builder \
#   FORK_REGISTRY=... ./scripts/fork/build-sandbox.sh
#
#   # Graviton / arm64 target:
#   TARGET_PLATFORM=linux/arm64 FORK_REGISTRY=... ./scripts/fork/build-sandbox.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT"

FORK_REGISTRY="${FORK_REGISTRY:?Set FORK_REGISTRY, e.g. 120354378950.dkr.ecr.us-east-1.amazonaws.com/ideaboxai-platform-core (must include the namespace path)}"
SNAPSHOT_TAG="${SNAPSHOT_TAG:-1.0.2}"
TARGET_PLATFORM="${TARGET_PLATFORM:-linux/amd64}"

# Build source: vendored copy (default) or a live platform checkout via SNAPSHOT_SRC.
if [[ -n "${SNAPSHOT_SRC:-}" ]]; then
  [[ -f "$SNAPSHOT_SRC/Dockerfile.snapshot" ]] \
    || { echo "!! SNAPSHOT_SRC set but $SNAPSHOT_SRC/Dockerfile.snapshot not found" >&2; exit 1; }
  BUILD_CONTEXT="$SNAPSHOT_SRC"
  BUILD_DOCKERFILE="$SNAPSHOT_SRC/Dockerfile.snapshot"
  SOURCE_DESC="live:$SNAPSHOT_SRC"
else
  BUILD_CONTEXT="images/daytona-sandbox"
  BUILD_DOCKERFILE="images/daytona-sandbox/Dockerfile"
  SOURCE_DESC="vendored:images/daytona-sandbox"
fi

export DOCKER_DEFAULT_PLATFORM="$TARGET_PLATFORM"
DST="${FORK_REGISTRY}/daytona-sandbox:${SNAPSHOT_TAG}"

HOST_PLATFORM="linux/$(docker version --format '{{.Server.Arch}}')"
if [[ "$TARGET_PLATFORM" != "$HOST_PLATFORM" ]]; then
  echo "!! Building $TARGET_PLATFORM on $HOST_PLATFORM — needs QEMU/binfmt and will be slow." >&2
  echo "!! If the toolchain crashes or hangs, build on a native $TARGET_PLATFORM machine." >&2
fi

# ECR never auto-creates repositories on push. Check up front so a missing repo
# fails here rather than after a full (slow) build.
if command -v aws >/dev/null 2>&1 && [[ "$FORK_REGISTRY" == *.dkr.ecr.*.amazonaws.com/* ]]; then
  REGION="$(sed -E 's/.*\.dkr\.ecr\.([^.]+)\.amazonaws\.com.*/\1/' <<<"$FORK_REGISTRY")"
  NAMESPACE="${FORK_REGISTRY#*/}"
  if ! aws ecr describe-repositories --region "$REGION" \
        --repository-names "${NAMESPACE}/daytona-sandbox" >/dev/null 2>&1; then
    echo "!! Missing ECR repository in ${REGION}: ${NAMESPACE}/daytona-sandbox" >&2
    echo "!! Create it, or ask DevOps to. ECR will not create it on push." >&2
    exit 1
  fi
  echo ">> Preflight OK: ${NAMESPACE}/daytona-sandbox exists in $REGION"
fi

echo ">> Building daytona-sandbox from ${SOURCE_DESC} (tag: $SNAPSHOT_TAG, platform: $TARGET_PLATFORM)"
docker build --platform "$TARGET_PLATFORM" -f "$BUILD_DOCKERFILE" -t "$DST" "$BUILD_CONTEXT"

echo ">> Pushing $DST"
docker push "$DST"

# Read the digest back from the registry — authoritative (see build-push.sh).
DIGESTS_FILE="dist/fork-sandbox-digest-${SNAPSHOT_TAG}.txt"
mkdir -p dist
digest="$(docker buildx imagetools inspect "$DST" --format '{{.Manifest.Digest}}')"
{
  echo "# tag:      $SNAPSHOT_TAG"
  echo "# source:   $SOURCE_DESC"
  echo "# platform: $TARGET_PLATFORM"
  echo "daytona-sandbox ${DST} ${FORK_REGISTRY}/daytona-sandbox@${digest}"
} | tee "$DIGESTS_FILE"

echo ">> Pushed. Immutable digest written to $DIGESTS_FILE"
echo ">> Deliver DEFAULT_SNAPSHOT_IMAGE as the digest pin above (or the :$SNAPSHOT_TAG tag if the repo is immutable)."
