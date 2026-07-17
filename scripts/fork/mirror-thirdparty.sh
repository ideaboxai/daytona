#!/usr/bin/env bash
# Mirror the third-party images this stack depends on into OUR registry, so a
# Docker Hub outage — or an upstream tag being moved or deleted — can't block a
# fresh deploy. Complements build-push.sh, which covers the 4 images we build.
#
# Uses `docker buildx imagetools create`, which copies the full manifest list
# registry-to-registry without pulling. That preserves every architecture, so the
# mirror stays valid whatever the deploy target runs (x86_64 or arm64). A
# pull/tag/push loop would silently flatten each image to this machine's arch.
#
# Two of the sources (minio:latest, docker-registry-ui:main) are MUTABLE tags:
# what you mirror is whatever they point at right now. That's precisely why the
# digest is captured below and pinned in the compose override.
#
# Requires a docker login to the ECR *host* — not the namespace path:
#   aws ecr get-login-password --region us-east-1 \
#     | docker login --username AWS --password-stdin 120354378950.dkr.ecr.us-east-1.amazonaws.com
#
# Usage:
#   FORK_REGISTRY=120354378950.dkr.ecr.us-east-1.amazonaws.com/ideaboxai-platform-core \
#     ./scripts/fork/mirror-thirdparty.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT"

FORK_REGISTRY="${FORK_REGISTRY:?Set FORK_REGISTRY, e.g. 120354378950.dkr.ecr.us-east-1.amazonaws.com/ideaboxai-platform-core (must include the namespace path)}"

# upstream image ref | our repo name
#
# Repo names match the ECR repositories exactly. They are deliberately NOT
# consistent — jaeger keeps its org prefix while dex, minio and otel dropped
# theirs. Do not tidy these into a pattern; pushes would land in repos that
# don't exist. Keep in sync with docker/docker-compose.yaml.
IMAGES=(
  "dexidp/dex:v2.42.0|dex"
  "joxit/docker-registry-ui:main|docker-registry-ui"
  "registry:2.8.2|registry"
  "jaegertracing/all-in-one:1.67.0|jaegertracing/all-in-one"
  "minio/minio:latest|minio"
  "otel/opentelemetry-collector-contrib:0.138.0|opentelemetry-collector-contrib"
)

# ECR never auto-creates repositories on push. Check all of them up front so a
# missing one fails here, not halfway through the mirror with 3 images already up.
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

DIGESTS_FILE="dist/fork-thirdparty-digests-$(date -u +%Y%m%d).txt"
mkdir -p dist
: > "$DIGESTS_FILE"

echo ">> Mirroring ${#IMAGES[@]} third-party images to $FORK_REGISTRY"
for entry in "${IMAGES[@]}"; do
  src="${entry%%|*}"
  repo="${entry##*|}"
  tag="${src##*:}"
  dst="${FORK_REGISTRY}/${repo}:${tag}"

  echo ">> $src -> $dst"
  docker buildx imagetools create --tag "$dst" "$src"

  # Read the digest back from the registry. Authoritative — unlike scraping push
  # output or trusting a local RepoDigests ordering.
  digest="$(docker buildx imagetools inspect "$dst" --format '{{.Manifest.Digest}}')"
  echo "${repo} ${dst} ${FORK_REGISTRY}/${repo}@${digest}" | tee -a "$DIGESTS_FILE"
done

echo ">> Mirrored. Digests written to $DIGESTS_FILE"
echo ">> Pin these into docker/docker-compose.registry.override.yaml"
