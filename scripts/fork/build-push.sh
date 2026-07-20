#!/usr/bin/env bash
#
# Copyright 2025 Daytona Platforms Inc.
# SPDX-License-Identifier: AGPL-3.0
#
# Build the 4 Daytona service images FROM SOURCE (not Docker Hub) and push them
# to OUR registry with an immutable, traceable tag. Removes the dependency on
# daytonaio/* Docker Hub images that may be removed now upstream is frozen.
#
# Uses the repo's existing build wiring: docker/docker-compose.build.override.yaml
# (each service -> apps/<svc>/Dockerfile with a build target). `docker compose
# build` tags each built image as its compose `image:` value, which we then
# retag to <FORK_REGISTRY>/daytona-<svc>:<TAG> and push.
#
# ARCHITECTURE: these are compiled locally, so they are single-arch. TARGET_PLATFORM
# must match the deploy target — an x86_64 image will not run on Graviton, and the
# failure only surfaces at deploy. Defaults to linux/amd64. Building a platform
# other than this machine's needs QEMU/binfmt and is slow.
# (scripts/fork/mirror-thirdparty.sh has no such constraint — it copies upstream
# manifest lists whole and keeps every architecture.)
#
# Requires a docker login to the ECR *host* — not the namespace path:
#   aws ecr get-login-password --region us-east-1 \
#     | docker login --username AWS --password-stdin 120354378950.dkr.ecr.us-east-1.amazonaws.com
#
# Usage:
#   FORK_REGISTRY=120354378950.dkr.ecr.us-east-1.amazonaws.com/ideaboxai-platform-core \
#     ./scripts/fork/build-push.sh
#
#   # Graviton / arm64 target:
#   TARGET_PLATFORM=linux/arm64 FORK_REGISTRY=... ./scripts/fork/build-push.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT"

FORK_REGISTRY="${FORK_REGISTRY:?Set FORK_REGISTRY, e.g. 120354378950.dkr.ecr.us-east-1.amazonaws.com/ideaboxai-platform-core (must include the namespace path)}"
TARGET_PLATFORM="${TARGET_PLATFORM:-linux/amd64}"
SHORT_SHA="$(git rev-parse --short HEAD)"
DATE="$(date -u +%Y%m%d)"
TAG="${TAG:-fork-${DATE}-${SHORT_SHA}}"

# Docker image tags cannot contain '/', but a caller (byoc-release.sh) passes a
# git-style tag like byoc/<client>/<date-sha>. Derive a tag-safe form for the
# image reference and the digest filename; keep the original TAG for provenance.
IMAGE_TAG="${TAG//[^A-Za-z0-9._-]/-}"

# Honoured by compose build for both the FROM pulls and the output image.
export DOCKER_DEFAULT_PLATFORM="$TARGET_PLATFORM"

# compose service | Docker Hub image name it builds as (from docker-compose.yaml).
# Indexed, not associative — associative arrays iterate in unspecified order,
# which scrambles the digest file between runs for no reason.
SERVICES=(
  "api|daytonaio/daytona-api"
  "proxy|daytonaio/daytona-proxy"
  "runner|daytonaio/daytona-runner"
  "ssh-gateway|daytonaio/daytona-ssh-gateway"
)

# `compose build` interpolates the ENTIRE compose file before it builds anything,
# so the deploy-time ${VAR:?} guards in docker-compose.yaml would otherwise block
# a build on RDS/ElastiCache endpoints the build never reads. Satisfy them with
# placeholders — these values are only meaningful at `up` time, and building must
# not depend on having the datastores provisioned yet.
export DB_HOST=build-time-placeholder
export DB_USERNAME=build-time-placeholder
export DB_PASSWORD=build-time-placeholder
export REDIS_HOST=build-time-placeholder

COMPOSE=(docker compose --env-file docker/.env \
  -f docker/docker-compose.yaml \
  -f docker/docker-compose.build.override.yaml)

HOST_PLATFORM="linux/$(docker version --format '{{.Server.Arch}}')"
if [[ "$TARGET_PLATFORM" != "$HOST_PLATFORM" ]]; then
  echo "!! Building $TARGET_PLATFORM on $HOST_PLATFORM — needs QEMU/binfmt and will be slow." >&2
  echo "!! If the toolchain crashes or hangs, build on a native $TARGET_PLATFORM machine." >&2
fi

# The tag claims to name a commit. If the tree is dirty it doesn't, and the
# resulting image is untraceable — which is the whole point of the tag.
if ! git diff --quiet HEAD 2>/dev/null; then
  echo "!! Working tree is dirty: tag $TAG names commit $SHORT_SHA but the image won't match it." >&2
fi

# ECR never auto-creates repositories on push. Check up front so a missing repo
# fails here rather than after a full (slow) build.
if command -v aws >/dev/null 2>&1 && [[ "$FORK_REGISTRY" == *.dkr.ecr.*.amazonaws.com/* ]]; then
  REGION="$(sed -E 's/.*\.dkr\.ecr\.([^.]+)\.amazonaws\.com.*/\1/' <<<"$FORK_REGISTRY")"
  NAMESPACE="${FORK_REGISTRY#*/}"
  missing=()
  for entry in "${SERVICES[@]}"; do
    svc="${entry%%|*}"
    aws ecr describe-repositories --region "$REGION" \
      --repository-names "${NAMESPACE}/daytona-${svc}" >/dev/null 2>&1 \
      || missing+=("${NAMESPACE}/daytona-${svc}")
  done
  if (( ${#missing[@]} )); then
    echo "!! Missing ECR repositories in ${REGION}:" >&2
    printf '     %s\n' "${missing[@]}" >&2
    echo "!! Create them, or ask DevOps to. ECR will not create them on push." >&2
    exit 1
  fi
  echo ">> Preflight OK: all ${#SERVICES[@]} ECR repositories exist in $REGION"
fi

# go.work.sum is gitignored and generated at build time; the three Go service
# Dockerfiles AND hack/computer-use/Dockerfile all `COPY go.work.sum`, so a fresh
# checkout fails with "failed to calculate checksum of ref" without it. Generate
# it in a golang container so this needs only Docker — no local Go toolchain.
if [[ ! -f go.work.sum ]]; then
  echo ">> Generating go.work.sum (Go services COPY it)"
  docker run --rm -v "$REPO_ROOT:/src" -w /src \
    -e GONOSUMDB=github.com/daytonaio/daytona golang:1.25 \
    sh -c 'go work sync || true; touch go.work.sum'
fi

# apps/runner/Dockerfile does `COPY dist/libs/computer-use-amd64`, a prebuilt,
# gitignored artifact `compose build` cannot produce. Built via
# hack/computer-use/Dockerfile, NOT the native build-*.sh path: that does a bare
# `go build` on x86_64, and computer-use's robotgo needs X11/CGO dev libs the build
# host may lack (fails with `undefined: Bitmap`). The Dockerfile bakes those deps in
# (libx11-dev, libxtst-dev, gcc, CGO_ENABLED=1). It COPYs go.work.sum, made above.
# amd64-only by design — the binary ships into sandboxes, not the runner image.
if [[ ! -f dist/libs/computer-use-amd64 ]]; then
  echo ">> Building computer-use (runner image dependency)"
  mkdir -p dist/libs
  docker build --platform linux/amd64 -t computer-use-amd64:build -f hack/computer-use/Dockerfile .
  docker run --rm -v "$REPO_ROOT/dist:/dist" computer-use-amd64:build
  test -f dist/libs/computer-use-amd64 || { echo "!! computer-use build produced no artifact" >&2; exit 1; }
fi

echo ">> Building service images from source (tag: $TAG, platform: $TARGET_PLATFORM)"
"${COMPOSE[@]}" build api proxy runner ssh-gateway

echo ">> Retagging + pushing to $FORK_REGISTRY"
DIGESTS_FILE="dist/fork-image-digests-${IMAGE_TAG}.txt"
mkdir -p dist
{
  echo "# tag:       $IMAGE_TAG"
  [[ "$IMAGE_TAG" != "$TAG" ]] && echo "# source tag: $TAG"
  echo "# platform:  $TARGET_PLATFORM"
  echo "# commit:    $(git rev-parse HEAD)"
} > "$DIGESTS_FILE"

for entry in "${SERVICES[@]}"; do
  svc="${entry%%|*}"
  src="${entry##*|}"                          # e.g. daytonaio/daytona-api (:latest)
  dst="${FORK_REGISTRY}/daytona-${svc}:${IMAGE_TAG}"
  docker tag "$src" "$dst"
  docker push "$dst"

  # Read the digest back from the registry — authoritative. The previous
  # `docker inspect {{index .RepoDigests 0}}` took whichever digest happened to
  # sit first in the local list, which is not necessarily the one just pushed:
  # a stale daytonaio/* digest from an earlier Hub pull could win and get pinned.
  digest="$(docker buildx imagetools inspect "$dst" --format '{{.Manifest.Digest}}')"
  echo "daytona-${svc} ${dst} ${FORK_REGISTRY}/daytona-${svc}@${digest}" | tee -a "$DIGESTS_FILE"
done

echo ">> Pushed. Immutable digests written to $DIGESTS_FILE"
echo ">> Pin these digests into docker/docker-compose.registry.override.yaml"
