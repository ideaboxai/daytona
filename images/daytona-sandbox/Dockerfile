# SYNCED-FROM: ideaboxai-multi-agent-service/scripts/snapshot_builder/Dockerfile.snapshot @23068a96
#
# Default Daytona sandbox base snapshot for BYOC delivery. Built + pushed to the
# delivery registry (repo `daytona-sandbox`) by scripts/fork/build-sandbox.sh, then
# registered as the default snapshot on first boot (DEFAULT_SNAPSHOT / DEFAULT_SNAPSHOT_IMAGE).
# This is the platform's application sandbox image — NOT a Daytona AGPL artifact.
# Keep in sync with the platform source above; build-sandbox.sh can build from a live
# checkout via SNAPSHOT_SRC instead of this vendored copy.
FROM python:3.12-slim-bookworm

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

# System packages
RUN apt-get update && apt-get install -y --no-install-recommends \
    nodejs npm \
    curl wget git \
    ffmpeg \
    imagemagick \
    tesseract-ocr \
    graphviz \
    sqlite3 \
    jq \
    && rm -rf /var/lib/apt/lists/*

# Python packages — pinned for reproducible builds
# numpy pinned to 1.x (2.0 has breaking ABI changes)
# Regenerate upstream: pip-compile scripts/snapshot_builder/requirements.in \
#             -o scripts/snapshot_builder/requirements-frozen.txt
COPY requirements-frozen.txt /tmp/requirements-frozen.txt
RUN pip install --no-cache-dir -r /tmp/requirements-frozen.txt

# Playwright — chromium only (smallest browser footprint)
RUN playwright install chromium --with-deps

# Node.js global packages
RUN npm install -g \
    pptxgenjs \
    sharp \
    typescript \
    ts-node \
    tsx \
    marked

# daytona user — required for /home/daytona/skills/ paths used by skill-sync
RUN useradd -m -u 1000 daytona
WORKDIR /home/daytona
USER daytona

CMD ["sleep", "infinity"]
