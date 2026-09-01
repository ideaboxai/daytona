# SYNCED-FROM: ideaboxai-multi-agent-service/scripts/snapshot_builder/Dockerfile.snapshot @23068a96
#
# Default Daytona sandbox base snapshot for BYOC delivery. Built + pushed to the
# delivery registry (repo `daytona-sandbox`) by scripts/fork/build-sandbox.sh, then
# registered as the default snapshot on first boot (DEFAULT_SNAPSHOT / DEFAULT_SNAPSHOT_IMAGE).
# This is the platform's application sandbox image — NOT a Daytona AGPL artifact.
# Keep in sync with the platform source above; build-sandbox.sh can build from a live
# checkout via SNAPSHOT_SRC instead of this vendored copy.
#
# ⚠ AHEAD OF THE SYNC SOURCE. The crawl4ai steps below come from CPD-6762, which changed
# only the platform's builder.py (the Daytona-SDK build path) — upstream's
# Dockerfile.snapshot was not part of that change and still lacks them. So a `SNAPSHOT_SRC`
# build, or a wholesale re-sync from upstream, produces an image WITHOUT crawl4ai and
# silently breaks crawl_page's sandbox execution path. Re-sync only after upstream's
# Dockerfile.snapshot has caught up.
FROM python:3.12-slim-bookworm

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

# Pinned BEFORE `playwright install` below, not left to default to $HOME/.cache: that
# step runs as root (useradd has not happened yet), so a $HOME-relative browser cache
# lands under /root and is invisible once execution switches to the `daytona` user —
# crawl4ai (CPD-6762) launches Chromium at runtime as that user and would find nothing
# there. Same fix shape as services/multi_agent's own Dockerfile.
ENV PLAYWRIGHT_BROWSERS_PATH=/opt/ms-playwright

# System packages
# poppler-utils supplies pdftoppm/pdfinfo, which pdf2image shells out to. Without it
# pdf2image raises PDFInfoNotInstalledError on every call — the package was installed
# but the capability never worked. (pytesseract/Wand/graphviz have their binaries below.)
RUN apt-get update && apt-get install -y --no-install-recommends \
    nodejs npm \
    curl wget git \
    ffmpeg \
    imagemagick \
    tesseract-ocr \
    poppler-utils \
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

# World-readable rather than chowned to `daytona`: nothing at runtime writes here, and
# the pinned absolute path above already means there is no per-user cache to keep in sync.
RUN chmod -R a+rX /opt/ms-playwright

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

# Warm crawl4ai's sqlite cache (~/.crawl4ai) at build time rather than on the first
# crawl a run makes — network-free, and this user's $HOME is real and writable
# (`useradd -m` above), unlike the service pod's read-only root. Doubles as a build-time
# assertion that the import which used to raise EROFS now succeeds as `daytona`.
RUN python3 -c 'import crawl4ai.async_database'

CMD ["sleep", "infinity"]
