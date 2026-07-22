#!/usr/bin/env bash
#
# Copyright 2025 Daytona Platforms Inc.
# SPDX-License-Identifier: AGPL-3.0
#
# Mirror the (now-frozen) upstream daytonaio/daytona repo into our own git host
# and repoint this clone's remotes: origin -> our fork, upstream -> read-only.
#
# Upstream went closed-source / frozen on 2026-06-11. This makes us independent
# of github.com/daytonaio/daytona staying convenient. See FORK.md.
#
# Usage:
#   FORK_REMOTE=git@github.com:your-org/daytona.git ./scripts/fork/mirror-upstream.sh
set -euo pipefail

UPSTREAM_URL="${UPSTREAM_URL:-git@github.com:daytonaio/daytona.git}"
FORK_REMOTE="${FORK_REMOTE:?Set FORK_REMOTE to your own git host, e.g. git@github.com:your-org/daytona.git}"
WORKDIR="${WORKDIR:-/tmp/daytona-mirror}"

echo ">> Full mirror clone of upstream (all branches, tags, history)"
rm -rf "$WORKDIR"
git clone --mirror "$UPSTREAM_URL" "$WORKDIR"

# A --mirror clone of a GitHub repo also carries read-only PR refs (refs/pull/*).
# GitHub rejects writing those to any repo ("deny updating a hidden ref"), which
# makes the push exit non-zero even though branches/tags pushed fine. Drop them
# so the mirror push is clean and re-runnable. We don't want upstream PR refs anyway.
echo ">> Stripping read-only refs/pull/* before push"
git -C "$WORKDIR" for-each-ref --format='delete %(refname)' 'refs/pull/*' \
  | git -C "$WORKDIR" update-ref --stdin || true

echo ">> Pushing full mirror to fork remote: $FORK_REMOTE"
git -C "$WORKDIR" remote add fork "$FORK_REMOTE"
git -C "$WORKDIR" push --mirror fork

echo ">> Repointing THIS working clone's remotes"
# origin -> our fork (read/write), upstream -> read-only source for last cherry-picks
git remote set-url origin "$FORK_REMOTE"
if git remote | grep -qx upstream; then
  git remote set-url upstream "$UPSTREAM_URL"
else
  git remote add upstream "$UPSTREAM_URL"
fi
# make upstream push a no-op to avoid accidental pushes to daytonaio
git remote set-url --push upstream DISABLED

echo ">> Remotes now:"
git remote -v
echo ">> Done. Our fork owns the source. Upstream kept read-only for final cherry-picks."
