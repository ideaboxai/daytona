# daytona-proxy — thin wrapper over the upstream image.
#
# Upstream base is alpine:3.22, which has no non-root user by default, so one is
# created here. Replays apps/proxy/Dockerfile's hardening (commit edda70ca8).
#
# The proxy binds 4003 (>1024) and reads config from env, so it needs no root.

ARG UPSTREAM_TAG=latest
FROM daytonaio/daytona-proxy:${UPSTREAM_TAG}

# Non-root runtime user (alpine has none by default).
# `|| true` so a rebuild against a base that already has appuser is not an error.
RUN adduser -D -H -u 10001 appuser || true

USER appuser
