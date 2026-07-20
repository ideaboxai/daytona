#!/usr/bin/env bash
# Mirror the 4 prebuilt daytonaio/* images from Docker Hub into OUR registry.
#
# INTERIM MEASURE. Upstream froze on 2026-06-11 and has stated the repo is
# unmaintained; nothing stops them removing the Docker Hub images. This copies
# them to our registry today so a deletion can't strand the deploy, without
# waiting on a working build toolchain.
#
# It does NOT replace build-push.sh:
#   - These are prebuilt binaries. We cannot patch them, and the non-root USER
#     in apps/*/Dockerfile does not apply — those need a real build.
#   - For BYOC, AGPL requires the Corresponding Source of the exact image shipped.
#     The commit behind daytonaio/daytona-api:latest is not provable from here.
#     Ship BYOC clients images built by build-push.sh, not these.
# Use these to de-risk the current deploy; move to build-push.sh images before
# hardening matters or a client deploy.
#
# Uses `docker buildx imagetools create` — copies the full manifest list
# registry-to-registry without pulling, preserving every architecture. A
# pull/tag/push loop would flatten each image to this machine's arch.
#
# The sources are untagged in docker-compose.yaml, i.e. :latest — a mutable tag
# that upstream has now stopped moving, so it is effectively the final image.
# That is exactly why the digest is captured below and pinned in the override.
#
# Requires a docker login to the ECR *host* — not the namespace path:
#   aws ecr get-login-password --region us-east-1 \
#     | docker login --username AWS --password-stdin 120354378950.dkr.ecr.us-east-1.amazonaws.com
#
# Usage:
#   FORK_REGISTRY=120354378950.dkr.ecr.us-east-1.amazonaws.com/ideaboxai-platform-core \
#     ./scripts/fork/mirror-daytona-hub.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT"

FORK_REGISTRY="${FORK_REGISTRY:?Set FORK_REGISTRY, e.g. 120354378950.dkr.ecr.us-east-1.amazonaws.com/ideaboxai-platform-core (must include the namespace path)}"

# Tagged hub-<date>, deliberately distinct from build-push.sh's fork-<date>-<sha>.
# The provenance differs and must stay legible from the tag alone: one is a copy
# of an opaque upstream binary, the other is built from a known commit.
TAG="${TAG:-hub-$(date -u +%Y%m%d)}"

# upstream image ref | our repo name — same ECR repos build-push.sh pushes to,
# so mirrored and built images coexist, distinguished only by tag.
IMAGES=(
  "daytonaio/daytona-api:latest|daytona-api"
  "daytonaio/daytona-proxy:latest|daytona-proxy"
  "daytonaio/daytona-runner:latest|daytona-runner"
  "daytonaio/daytona-ssh-gateway:latest|daytona-ssh-gateway"
)

# ECR never auto-creates repositories on push. Check all of them up front so a
# missing one fails here, not halfway through with 2 images already up.
if command -v aws >/dev/null 2>&1 && [[ "$FORK_REGISTRY" == *.dkr.ecr.*.amazonaws.com/* ]]; then
  REGION="$(sed -E 's/.*\.dkr\.ecr\.([^.]+)\.amazonaws\.com.*/\1/' <<<"$FORK_REGISTRY")"
  NAMESPACE="${FORK_REGISTRY#*/}"
  missing=()
  for entry in "${IMAGES[@]}"; do
    repo="${entry##*|}"
    aws ecr describe-repositories --region "$REGION" \
      --repository-names "${NAMESPACE}/${repo}" >/dev/null 2>&1 || missing+=("${NAMESPACE}/${repo}")
  done
  if (( ${#missing[@]} )); then
    echo "!! Missing ECR repositories in ${REGION}:" >&2
    printf '     %s\n' "${missing[@]}" >&2
    echo "!! Create them, or ask DevOps to. ECR will not create them on push." >&2
    exit 1
  fi
  echo ">> Preflight OK: all ${#IMAGES[@]} ECR repositories exist in $REGION"
fi

DIGESTS_FILE="dist/fork-hub-mirror-digests-${TAG}.txt"
mkdir -p dist
{
  echo "# tag:    $TAG"
  echo "# source: prebuilt daytonaio/* from Docker Hub (NOT built from source)"
  echo "# note:   not for BYOC client deploys — use build-push.sh images"
} > "$DIGESTS_FILE"

echo ">> Mirroring ${#IMAGES[@]} daytonaio images to $FORK_REGISTRY (tag: $TAG)"
for entry in "${IMAGES[@]}"; do
  src="${entry%%|*}"
  repo="${entry##*|}"
  dst="${FORK_REGISTRY}/${repo}:${TAG}"

  echo ">> $src -> $dst"
  docker buildx imagetools create --tag "$dst" "$src"

  # Read the digest back from the registry — authoritative.
  digest="$(docker buildx imagetools inspect "$dst" --format '{{.Manifest.Digest}}')"
  echo "${repo} ${dst} ${FORK_REGISTRY}/${repo}@${digest}" | tee -a "$DIGESTS_FILE"
done

echo ">> Mirrored. Digests written to $DIGESTS_FILE"
echo ">> Pin these into docker/docker-compose.registry.override.yaml"
echo ">> Reminder: interim only — build from source (build-push.sh) before hardening or BYOC."
