# daytona-runner — thin wrapper over the upstream image.
#
# Deliberately adds NOTHING. It exists so all four services are produced and
# tagged by one uniform pipeline; a wrapper that only re-tags is preferable to a
# special case in the build script.
#
# The runner MUST stay root. It hosts the inner Docker-in-Docker daemon that runs
# sandboxes (privileged + SYS_ADMIN + /dev/fuse in compose); a USER directive here
# would break sandbox creation. Isolation is enforced at the sandbox boundary, not
# by dropping the runner's own privileges. This matches apps/runner/Dockerfile,
# which is the one service edda70ca8 deliberately left as root, and
# docker-compose.hardening.override.yaml, which omits the runner for the same reason.
#
# Wrapping also sidesteps the from-source build's `COPY dist/libs/computer-use-amd64`
# — a prebuilt artifact the upstream image already contains.

ARG UPSTREAM_TAG=latest
FROM daytonaio/daytona-runner:${UPSTREAM_TAG}
