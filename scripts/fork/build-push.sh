#!/usr/bin/env bash
# Build the 4 Daytona service images FROM SOURCE (not Docker Hub) and push them
# to OUR registry with an immutable, traceable tag. Removes the dependency on
# daytonaio/* Docker Hub images that may be removed now upstream is frozen.
#
# Uses the repo's existing build wiring: docker/docker-compose.build.override.yaml
# (each service -> apps/<svc>/Dockerfile with a build target). `docker compose
# build` tags each built image as its compose `image:` value, which we then
# retag to <FORK_REGISTRY>/<svc>:<TAG> and push.
#
# Usage:
#   FORK_REGISTRY=123456789.dkr.ecr.us-east-1.amazonaws.com ./scripts/fork/build-push.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT"

FORK_REGISTRY="${FORK_REGISTRY:?Set FORK_REGISTRY, e.g. 123456789.dkr.ecr.us-east-1.amazonaws.com or registry.example.com/daytona}"
SHORT_SHA="$(git rev-parse --short HEAD)"
DATE="$(date -u +%Y%m%d)"
TAG="${TAG:-fork-${DATE}-${SHORT_SHA}}"

COMPOSE=(docker compose --env-file docker/.env \
  -f docker/docker-compose.yaml \
  -f docker/docker-compose.build.override.yaml)

# compose service -> Docker Hub image name it builds as (from docker-compose.yaml)
declare -A SVC_IMAGE=(
  [api]=daytonaio/daytona-api
  [proxy]=daytonaio/daytona-proxy
  [runner]=daytonaio/daytona-runner
  [ssh-gateway]=daytonaio/daytona-ssh-gateway
)

echo ">> Building service images from source (tag: $TAG)"
"${COMPOSE[@]}" build api proxy runner ssh-gateway

echo ">> Retagging + pushing to $FORK_REGISTRY"
DIGESTS_FILE="dist/fork-image-digests-${TAG}.txt"
mkdir -p dist
: > "$DIGESTS_FILE"
for svc in "${!SVC_IMAGE[@]}"; do
  src="${SVC_IMAGE[$svc]}"                    # e.g. daytonaio/daytona-api (:latest)
  dst="${FORK_REGISTRY}/daytona-${svc}:${TAG}"
  docker tag "$src" "$dst"
  docker push "$dst"
  # capture the immutable digest for pinning
  digest="$(docker inspect --format='{{index .RepoDigests 0}}' "$dst" 2>/dev/null || true)"
  echo "daytona-${svc} ${dst} ${digest}" | tee -a "$DIGESTS_FILE"
done

echo ">> Pushed. Immutable digests written to $DIGESTS_FILE"
echo ">> Pin these digests into docker/docker-compose.registry.override.yaml"
