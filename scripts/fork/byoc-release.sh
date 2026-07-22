#!/usr/bin/env bash
# BYOC release: cut ONE immutable deploy point for a client and produce the
# AGPL-3.0 Corresponding Source handoff for the Daytona SERVER we convey to them.
#
# Conveying (deploying to a client's servers) triggers AGPL-3.0: the client must
# receive the complete source of the exact server version running. This script
# makes that a single, reproducible, auditable step. See FORK.md.
#
# What it does NOT touch: your proprietary application. The Daytona SDK your app
# uses is Apache-2.0; the server we hand over here is the only AGPL artifact.
#
# Usage:
#   CLIENT=acmecorp \
#   CLIENT_REGISTRY=123456789.dkr.ecr.eu-west-1.amazonaws.com \
#   ./scripts/fork/byoc-release.sh
#
#   # source-only (skip image build/push), e.g. to regenerate a past handoff:
#   CLIENT=acmecorp SKIP_IMAGES=1 ./scripts/fork/byoc-release.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT"

CLIENT="${CLIENT:?Set CLIENT (lowercase slug), e.g. acmecorp}"
VENDOR="${VENDOR:-IdeaboxAI}"
CONTACT="${CONTACT:-legal@ideaboxai.com}"
# UTC date passed in is allowed; default to date command otherwise.
DATE_UTC="${DATE_UTC:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}"
DAY="${DAY:-$(date -u +%Y%m%d)}"

if ! [[ "$CLIENT" =~ ^[a-z0-9][a-z0-9-]*$ ]]; then
  echo "::error:: CLIENT must be a lowercase slug (a-z0-9-): got '$CLIENT'" >&2
  exit 1
fi

# Refuse to release from a dirty tree — the source archive must match what runs.
if [ -n "$(git status --porcelain --untracked-files=no)" ]; then
  echo "::error:: working tree has uncommitted changes; commit or stash before a BYOC release." >&2
  git status --short
  exit 1
fi

SHA="$(git rev-parse --short HEAD)"
FULL_SHA="$(git rev-parse HEAD)"
TAG="byoc/${CLIENT}/${DAY}-${SHA}"
OUTDIR="dist/byoc/${CLIENT}/${DAY}-${SHA}"
ARCHIVE="daytona-src-${CLIENT}-${SHA}.tar.gz"

mkdir -p "$OUTDIR"

echo ">> 1/4  Tagging immutable deploy point: $TAG"
if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
  echo "     tag already exists, reusing it (idempotent re-run)"
else
  git tag -a "$TAG" -m "BYOC deploy for ${CLIENT} @ ${FULL_SHA}"
  git push origin "$TAG"
fi

echo ">> 2/4  Bundling Corresponding Source of $TAG"
# git archive captures the exact tree at the tag — the AGPL Corresponding Source.
git archive --format=tar.gz --prefix="daytona-${SHA}/" -o "${OUTDIR}/${ARCHIVE}" "$TAG"

echo ">> 3/4  Generating WRITTEN_OFFER.txt"
sed \
  -e "s|__CLIENT__|${CLIENT}|g" \
  -e "s|__SOURCE_ARCHIVE__|${ARCHIVE}|g" \
  -e "s|__TAG__|${TAG}|g" \
  -e "s|__COMMIT__|${FULL_SHA}|g" \
  -e "s|__DATE__|${DATE_UTC}|g" \
  -e "s|__VENDOR__|${VENDOR}|g" \
  -e "s|__CONTACT__|${CONTACT}|g" \
  scripts/fork/templates/WRITTEN_OFFER.template.txt > "${OUTDIR}/WRITTEN_OFFER.txt"

# checksum so the client (and you) can prove archive integrity later
( cd "$OUTDIR" && sha256sum "$ARCHIVE" > "${ARCHIVE}.sha256" )

echo ">> 4/4  Building + pushing server images from $TAG"
if [ "${SKIP_IMAGES:-0}" = "1" ]; then
  echo "     SKIP_IMAGES=1 -> skipping image build/push"
else
  : "${CLIENT_REGISTRY:?Set CLIENT_REGISTRY (or SKIP_IMAGES=1), e.g. <acct>.dkr.ecr.<region>.amazonaws.com}"
  TAG="$TAG" FORK_REGISTRY="$CLIENT_REGISTRY" ./scripts/fork/build-push.sh

  # Default sandbox snapshot (11th image) — opt-in: it versions on its own cadence
  # (SNAPSHOT_TAG), so it is NOT rebuilt on every server release. Set BUILD_SANDBOX=1
  # to (re)build + push it into the same build store as the 4 server images.
  if [ "${BUILD_SANDBOX:-0}" = "1" ]; then
    FORK_REGISTRY="$CLIENT_REGISTRY" ./scripts/fork/build-sandbox.sh
  fi

  # Two-stage delivery: if a client-facing release namespace is given, promote all
  # 11 images (4 server + 6 third-party + sandbox) from the build store
  # (CLIENT_REGISTRY) into it, so the client pulls everything from one namespace.
  # The sandbox must already exist in CLIENT_REGISTRY (this run or a prior one).
  if [ -n "${RELEASE_REGISTRY:-}" ]; then
    IMAGE_TAG="${TAG//[^A-Za-z0-9._-]/-}"
    SRC_REGISTRY="$CLIENT_REGISTRY" DST_REGISTRY="$RELEASE_REGISTRY" \
      FORK_TAG="$IMAGE_TAG" ./scripts/fork/promote.sh
  fi
fi

# Append to the compliance ledger (create header if missing).
LEDGER="BYOC_LEDGER.md"
if [ ! -f "$LEDGER" ]; then
  {
    echo "# BYOC delivery ledger (AGPL-3.0 compliance)"
    echo
    echo "One row per client deploy. Proof of which source we handed to whom."
    echo
    echo "| Client | Tag | Commit | Delivered (UTC) | Artifacts |"
    echo "|--------|-----|--------|-----------------|-----------|"
  } > "$LEDGER"
fi
echo "| ${CLIENT} | ${TAG} | ${SHA} | ${DATE_UTC} | source+offer+sha256$( [ "${SKIP_IMAGES:-0}" = "1" ] && echo "" || echo "+images" ) |" >> "$LEDGER"

echo
echo ">> Done. Handoff bundle for ${CLIENT}:"
echo "     ${OUTDIR}/${ARCHIVE}"
echo "     ${OUTDIR}/${ARCHIVE}.sha256"
echo "     ${OUTDIR}/WRITTEN_OFFER.txt"
echo ">> Ledger updated: ${LEDGER} (commit it)."
echo ">> Deliver the bundle to ${CLIENT} together with the deployment."
