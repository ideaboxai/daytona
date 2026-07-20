# daytona-api — thin wrapper over the upstream image.
#
# Upstream base is node:24-slim, which already ships a `node` user at uid 1000.
# Replays apps/api/Dockerfile's hardening (commit edda70ca8) without rebuilding
# ~2GB of Node/Nx toolchain from source.
#
# Build context is irrelevant — nothing is COPYed in. Kept at repo root for
# consistency with the other wrappers.

ARG UPSTREAM_TAG=latest
FROM daytonaio/daytona-api:${UPSTREAM_TAG}

# Drop privileges at runtime. The upstream image runs as root.
USER node
