# daytona-ssh-gateway — thin wrapper over the upstream image.
#
# Upstream base is alpine:3.22. Replays apps/ssh-gateway/Dockerfile's hardening
# (commit edda70ca8): the gateway binds 2222 (>1024) and reads its keys from env,
# so it needs no root privileges.

ARG UPSTREAM_TAG=latest
FROM daytonaio/daytona-ssh-gateway:${UPSTREAM_TAG}

# Non-root runtime user (alpine has none by default).
# `|| true` so a rebuild against a base that already has appuser is not an error.
RUN adduser -D -H -u 10001 appuser || true

USER appuser
