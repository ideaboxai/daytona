#!/usr/bin/env bash
#
# Copyright 2025 Daytona Platforms Inc.
# SPDX-License-Identifier: AGPL-3.0
#
# Promote a client's full image set from the canonical BUILD store
# (…/ideaboxai-platform-core, where build-push.sh / build-sandbox.sh /
# mirror-thirdparty.sh land) to the client-facing RELEASE namespace
# (…/ideaboxai-release/<client>, which the client's cluster actually pulls from).
#
# Two-stage delivery: images are BUILT once into platform-core, then PROMOTED per
# client into their release namespace. This copies all 11 delivered images so the
# client pulls every image from ONE namespace — never a split (10 from build, 1
# from release).
#
# Uses `docker buildx imagetools create` (registry-to-registry manifest copy, no
# pull) so every architecture is preserved, same as mirror-thirdparty.sh.
#
# Requires a docker login to the ECR *host* (source and destination share the
# 120354378950 host, so one login covers both):
#   aws ecr get-login-password --region us-east-1 \
#     | docker login --username AWS --password-stdin 120354378950.dkr.ecr.us-east-1.amazonaws.com
#
# Usage:
#   SRC_REGISTRY=120354378950.dkr.ecr.us-east-1.amazonaws.com/ideaboxai-platform-core \
#   DST_REGISTRY=120354378950.dkr.ecr.us-east-1.amazonaws.com/ideaboxai-release/actian \
#   FORK_TAG=byoc-actian-20260720-79cb1970f \
#     ./scripts/fork/promote.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT"

SRC_REGISTRY="${SRC_REGISTRY:?Set SRC_REGISTRY (build namespace, e.g. .../ideaboxai-platform-core)}"
DST_REGISTRY="${DST_REGISTRY:?Set DST_REGISTRY (client release namespace, e.g. .../ideaboxai-release/actian)}"
FORK_TAG="${FORK_TAG:?Set FORK_TAG, e.g. byoc-actian-20260720-79cb1970f (tag for the 4 server images)}"
SNAPSHOT_TAG="${SNAPSHOT_TAG:-1.0.2}"

# repo[:tag] entries relative to the namespace. The 4 server images carry FORK_TAG;
# the 6 third-party carry their pinned upstream tags (KEEP IN SYNC with
# mirror-thirdparty.sh / docker-compose.yaml); the sandbox carries SNAPSHOT_TAG.
REPO_TAGS=()
for svc in api proxy runner ssh-gateway; do REPO_TAGS+=("daytona-${svc}:${FORK_TAG}"); done
REPO_TAGS+=(
  "dex:v2.42.0"
  "docker-registry-ui:main"
  "registry:2.8.2"
  "jaegertracing/all-in-one:1.67.0"
  "minio:latest"
  "opentelemetry-collector-contrib:0.138.0"
)
REPO_TAGS+=("daytona-sandbox:${SNAPSHOT_TAG}")

# ECR never auto-creates repositories on push. Verify all 11 exist under DST up
# front so a missing repo fails here, not partway through the promote.
if command -v aws >/dev/null 2>&1 && [[ "$DST_REGISTRY" == *.dkr.ecr.*.amazonaws.com/* ]]; then
  REGION="$(sed -E 's/.*\.dkr\.ecr\.([^.]+)\.amazonaws\.com.*/\1/' <<<"$DST_REGISTRY")"
  NAMESPACE="${DST_REGISTRY#*/}"
  missing=()
  for entry in "${REPO_TAGS[@]}"; do
    repo="${entry%:*}"
    aws ecr describe-repositories --region "$REGION" \
      --repository-names "${NAMESPACE}/${repo}" >/dev/null 2>&1 || missing+=("${NAMESPACE}/${repo}")
  done
  if (( ${#missing[@]} )); then
    echo "!! Missing ECR repositories in ${REGION} under ${NAMESPACE}:" >&2
    printf '     %s\n' "${missing[@]}" >&2
    echo "!! Create them, or ask DevOps to. ECR will not create them on push." >&2
    exit 1
  fi
  echo ">> Preflight OK: all ${#REPO_TAGS[@]} destination repositories exist in $REGION"
fi

DIGESTS_FILE="dist/fork-promote-digests-$(date -u +%Y%m%d).txt"
mkdir -p dist
{
  echo "# promote: $SRC_REGISTRY -> $DST_REGISTRY"
  echo "# fork_tag: $FORK_TAG   snapshot_tag: $SNAPSHOT_TAG"
} > "$DIGESTS_FILE"

echo ">> Promoting ${#REPO_TAGS[@]} images: $SRC_REGISTRY -> $DST_REGISTRY"
for entry in "${REPO_TAGS[@]}"; do
  repo="${entry%:*}"
  tag="${entry##*:}"
  src="${SRC_REGISTRY}/${repo}:${tag}"
  dst="${DST_REGISTRY}/${repo}:${tag}"

  echo ">> $src -> $dst"
  docker buildx imagetools create --tag "$dst" "$src"

  digest="$(docker buildx imagetools inspect "$dst" --format '{{.Manifest.Digest}}')"
  echo "${repo} ${dst} ${DST_REGISTRY}/${repo}@${digest}" | tee -a "$DIGESTS_FILE"
done

echo ">> Promoted ${#REPO_TAGS[@]} images. Digests written to $DIGESTS_FILE"
echo ">> Clients pull from: $DST_REGISTRY (set FORK_REGISTRY to this when bundling/installing)."
