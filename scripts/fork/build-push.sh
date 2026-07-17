#!/usr/bin/env bash
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

# apps/runner/Dockerfile does `COPY dist/libs/computer-use-amd64`, a prebuilt
# artifact that is gitignored and NOT produced by `compose build` — upstream's CI
# builds it in a separate job and passes it between jobs as an artifact. Without
# it the runner build dies on a missing COPY source, so build it here.
#
# It is amd64-only by design: the binary ships into sandboxes rather than running
# in the runner image, and upstream feeds the same amd64 artifact to both its
# amd64 and arm64 image builds. So this does not vary with TARGET_PLATFORM.
# Called directly rather than via `nx run computer-use:build-amd64` — the nx target
# only shells out to this script, and going direct avoids needing node_modules.
# On x86_64 it is a native `go build`; on other hosts the script cross-builds.
if [[ ! -f dist/libs/computer-use-amd64 ]]; then
  echo ">> Building computer-use (prebuilt dependency of the runner image)"
  ./hack/computer-use/build-computer-use-amd64.sh
fi

echo ">> Building service images from source (tag: $TAG, platform: $TARGET_PLATFORM)"
"${COMPOSE[@]}" build api proxy runner ssh-gateway

echo ">> Retagging + pushing to $FORK_REGISTRY"
DIGESTS_FILE="dist/fork-image-digests-${TAG}.txt"
mkdir -p dist
{
  echo "# tag:      $TAG"
  echo "# platform: $TARGET_PLATFORM"
  echo "# commit:   $(git rev-parse HEAD)"
} > "$DIGESTS_FILE"

for entry in "${SERVICES[@]}"; do
  svc="${entry%%|*}"
  src="${entry##*|}"                          # e.g. daytonaio/daytona-api (:latest)
  dst="${FORK_REGISTRY}/daytona-${svc}:${TAG}"
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
