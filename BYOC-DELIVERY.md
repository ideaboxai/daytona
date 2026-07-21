# BYOC delivery — operator guide (internal)

How **we** produce and deliver a Daytona sandbox deployment to a client, and
rehearse it before handing over. Client-facing steps live in
`docker/CLIENT-INSTALL.md` (which ships inside the source archive). AGPL background
is in `FORK.md`.

---

## 0. The model (read once)

```
Client licenses OUR app (proprietary)
        │  app calls Daytona SDK  ← Apache-2.0, over API — permissive
        ▼
Daytona sandbox SERVER (AGPL-3.0)  ← we deliver + they run as infra
```

- Only the **Daytona server** is AGPL. Our app uses the **SDK over the API** — no
  copyleft reach — so the app stays proprietary. **Never** weld app code into the
  server; integrate only via SDK/API.
- Delivering the server to a client is *conveying* under AGPL-3.0 → the client must
  receive the **Corresponding Source** of the exact version. `byoc-release.sh`
  automates that.

**A release produces (per client):**
| Artifact | What | Where |
|---|---|---|
| Git tag `byoc/<client>/<date>-<sha>` | immutable deploy point | pushed to origin |
| `daytona-src-<client>-<sha>.tar.gz` (+`.sha256`) | AGPL Corresponding Source (contains `docker/`) | `dist/byoc/<client>/...` (gitignored) |
| `WRITTEN_OFFER.txt` | AGPL §6 notice | same dir |
| 4 server images `daytona-{api,proxy,runner,ssh-gateway}:byoc-<client>-<date>-<sha>` | from-source, hardened | our ECR |
| Row in `BYOC_LEDGER.md` | compliance trail | committed |

---

## 1. Prerequisites

- Clean checkout of this repo (`byoc-release.sh` refuses a dirty tree).
- A path to push **from-source** images into our ECR (see §3 — this is the part with
  a real gotcha).
- The client's **12-digit AWS account id** (for the pull grant, §4).
- Confirm the app/server boundary still holds (no proprietary code in `apps/`,`libs/`).

---

## 2. Cut the release

```bash
# from a clean checkout, on the commit you want to ship:
CLIENT=<slug> ./scripts/fork/byoc-release.sh          # full: tag + source + offer + images
# or, source/offer only (validate first, images later):
CLIENT=<slug> SKIP_IMAGES=1 ./scripts/fork/byoc-release.sh
```

This tags the commit, `git archive`s the source, renders the written offer + sha256,
appends the ledger row, and (unless `SKIP_IMAGES=1`) builds + pushes the images.

- The tag is **idempotent** — re-runs reuse it. So `SKIP_IMAGES=1` then a full run on
  the same commit is fine.
- The source archive **regenerates byte-identical** from the tag anywhere:
  `git archive --format=tar.gz --prefix="daytona-<sha>/" -o out.tar.gz byoc/<client>/<date>-<sha>`.
  The **tag** is the source of truth, not the file.
- Commit `BYOC_LEDGER.md` after each run.

---

## 3. Get from-source images into our ECR (the creds reality)

The images MUST be **from source** at the tagged commit — not the `hub-*` mirror
(raw upstream, root, no AGPL provenance). Two ways, depending on the target account:

**A. Platform-core account (`120354378950`, OIDC-only — no local push keys).**
Images land here via the **GitHub Actions workflow** (`dev-ecr-oidc.yml`), which
builds from source and pushes via OIDC. A laptop cannot `docker push` here. To ship a
`byoc-*` tag through it, the workflow must build from the byoc tag (its semver check
rejects `byoc-*` tags today — adapt the workflow or push from a host that has a role
in this account).

**B. An account you hold push creds for (e.g. `304038454586`/`ideaboxai`).**
Run `build-push.sh` directly, **from the tagged commit** so the image matches the
source you hand over:
```bash
git fetch origin --tags && git checkout byoc/<client>/<date>-<sha>
aws ecr get-login-password --region us-east-1 \
  | docker login --username AWS --password-stdin <ACCT>.dkr.ecr.us-east-1.amazonaws.com
TAG=byoc/<client>/<date>-<sha> \
FORK_REGISTRY=<ACCT>.dkr.ecr.us-east-1.amazonaws.com/<namespace> \
  ./scripts/fork/build-push.sh
```
`build-push.sh` sanitizes the tag's `/` → `-` (Docker tags forbid `/`), so images push
as `byoc-<client>-<date>-<sha>`.

> **The #1 gotcha:** `build-push.sh` preflight saying *"Missing ECR repositories"* when
> the repos clearly exist almost always means **you're authed to the wrong account** —
> `describe-repositories` queries the *caller's* account. Check `aws sts
> get-caller-identity` matches the registry account before anything else.

Verify the pushed images are the hardened from-source ones (not a mirror):
```bash
docker image inspect <ACCT>.../daytona-api:byoc-... --format '{{.Config.User}}'   # -> node
docker image inspect <ACCT>.../daytona-proxy:byoc-... --format '{{.Config.User}}' # -> appuser
# runner stays root by design (Docker-in-Docker)
```

---

## 4. Package the OFFLINE bundle (air-gapped clients — the default)

Air-gapped clients cannot pull from our registry, so ship the images **in the
bundle**. After the from-source images exist (§3, present locally or pulled):

```bash
CLIENT=<slug> \
FORK_REGISTRY=<acct>.dkr.ecr.<region>.amazonaws.com/<namespace> \
FORK_TAG=byoc-<slug>-<date>-<sha> \
BYOC_DIR=dist/byoc/<slug>/<date>-<sha> \
  ./scripts/fork/byoc-bundle.sh
```

Produces one file — `dist/byoc/<slug>/daytona-<slug>-<tag>.bundle.tar.gz` — containing
`images.tar` (all 10 images), the compose + configs, `install.sh`, and the AGPL source
archive + written offer. The client extracts it and runs `./install.sh` (loads images,
prompts ~6 settings, generates secrets, brings up). `docker save` captures the local
platform only — build/pull for the client's arch (default amd64).

## 4-alt. Grant the client pull from our ECR (client reaches our registry)

The client pulls from our ECR instead of loading `images.tar` — the model actian
uses (their nodes pull from our ECR, same as our app). Two sub-cases by whether the
client's network can reach Docker Hub.

**If the client canNOT reach Docker Hub (e.g. actian) — mirror the 6 third-party into
our ECR too, so all 10 live there:**
```bash
FORK_REGISTRY=<host>/<namespace> ./scripts/fork/mirror-thirdparty.sh   # 6 third-party -> our ECR
```
This pushes to the repos `dex`, `docker-registry-ui`, `registry`,
`jaegertracing/all-in-one`, `minio`, `opentelemetry-collector-contrib` — matching
`docker-compose.registry.override.yaml`. The client deploys with `IMAGE_SOURCE=registry`
(adds that override) so **all 10** pull from `FORK_REGISTRY`. Grant pull on **all 10**
repos below (add the 6 third-party repo names to the loop).

**Grant cross-account pull** (revocable; never push). For the actian case list all 10
repos; for a Hub-connected client, just the 4 `daytona-*`:
```bash
for repo in daytona-api daytona-proxy daytona-runner daytona-ssh-gateway \
            dex docker-registry-ui registry jaegertracing/all-in-one minio \
            opentelemetry-collector-contrib; do
  aws ecr set-repository-policy --region <region> \
    --repository-name <namespace>/$repo \
    --policy-text '{
      "Version":"2012-10-17",
      "Statement":[{"Sid":"AllowClientPull","Effect":"Allow",
        "Principal":{"AWS":"arn:aws:iam::<CLIENT_ACCOUNT_ID>:root"},
        "Action":["ecr:GetDownloadUrlForLayer","ecr:BatchGetImage","ecr:BatchCheckLayerAvailability"]}]}'
done
```
Hand the client `docker/CLIENT-INSTALL-CONNECTED.md` + the registry host / namespace /
tag / region. (To push into the client's OWN ECR instead, point `FORK_REGISTRY` at
theirs in §3 and skip the grant.)

---

## 5. Dress-rehearse on a bare EC2 (do this before every first client deploy)

Mimic the client exactly: start from a **fresh host**, use **only the delivered
artifacts** (source archive + image pull), **their-style datastores** (throwaway,
not our prod), and finish with a **sandbox functional test**.

### 5a. Bootstrap an empty EC2 (Ubuntu)
```bash
# Docker + compose plugin + aws cli
sudo apt-get update
sudo apt-get install -y docker.io docker-compose-plugin awscli
sudo systemctl enable --now docker
sudo usermod -aG docker "$USER"      # then re-login so docker works without sudo

# mount-s3 — the runner bind-mounts /usr/bin/mount-s3; missing = silent runner failure
wget -q https://s3.amazonaws.com/mountpoint-s3-release/latest/x86_64/mount-s3.deb
sudo apt-get install -y ./mount-s3.deb
ls -l /usr/bin/mount-s3 /dev/fuse     # both must exist
```
The host also needs **ECR pull access** to the registry from §3/§4 (instance role, or
`aws configure` with creds that can pull).

### 5b. Throwaway datastores (simulate the client's managed Postgres/Redis)
```bash
docker network create actian-net
docker run -d --name pg --network actian-net -e POSTGRES_USER=daytona \
  -e POSTGRES_PASSWORD=rehearsal -e POSTGRES_DB=daytona postgres:18
docker run -d --name redis --network actian-net redis:7
```

### 5c. Receive artifacts as the client would (no clone)
```bash
mkdir ~/rehearsal && cd ~/rehearsal
# copy in the delivered bundle (scp), OR regenerate from the tag if this host has the repo:
#   git -C <repo> archive --format=tar.gz --prefix="daytona-<sha>/" \
#     -o ~/rehearsal/daytona-src-<client>-<sha>.tar.gz byoc/<client>/<date>-<sha>
sha256sum -c daytona-src-<client>-<sha>.tar.gz.sha256
tar xzf daytona-src-<client>-<sha>.tar.gz
cd daytona-<sha>
```

### 5d. Configure + bring up
Follow `docker/CLIENT-INSTALL.md` from step 2: `docker login`, fill `docker/.env`
(`FORK_TAG=byoc-<client>-...`, `DB_HOST=pg`, `REDIS_HOST=redis`, TLS off, `EC2_HOST`),
generate the dex IP config, and:
```bash
docker compose --env-file docker/.env \
  -f docker/docker-compose.yaml \
  -f docker/docker-compose.ec2-http.override.yaml \
  --network actian-net up -d      # or attach pg/redis to the daytona network
```
(Datastores + stack must share a network. If pg/redis are on `actian-net`, put the
stack there too, or publish pg/redis on host ports and point `DB_HOST`/`REDIS_HOST` at
the host IP.)

### 5e. Verify — boot AND a real sandbox
Wait for `🚀 Daytona API is running`, then run the acceptance test in
`docker/CLIENT-INSTALL.md` (create a sandbox, exec, delete). That exercises
runner + ssh-gateway + proxy on the delivered images — the real proof.

### 5f. Tear down
```bash
docker compose ... down
docker rm -f pg redis && docker network rm actian-net
```

### How the rehearsal legitimately differs from the client
Datastores (throwaway vs their managed) and access (HTTP-IP vs their HTTPS-domain).
Images, compose, dex, boot chain, and sandbox lifecycle are identical. Sandbox port
previews (wildcard subdomains) are the one thing untested over IP.

---

## 6. Deliver to the client

**Air-gapped (default):** hand over the single offline bundle from §4 —
`daytona-<client>-<tag>.bundle.tar.gz` + `.sha256`. It self-contains images, compose,
installer, and the AGPL source + offer. Client experience:

```
tar xzf daytona-<client>-<tag>.bundle.tar.gz && cd daytona-<client>-<tag>
./install.sh          # loads images, ~6 prompts, generates secrets, brings up
```
No git, no build, no registry access. Point them at `README.txt` (entrypoint) and
`docker/CLIENT-INSTALL.md` (detail), both inside the bundle.

**Air-gapped WITH an internal registry (e.g. actian):** same offline bundle, but the
client seeds their own registry once instead of loading on every node — reuses the
exact channel their other apps already pull from. In the bundle:
```
./seed-registry.sh                                        # loads images.tar, pushes all 10 to their registry
IMAGE_SOURCE=registry FORK_REGISTRY=<prefix> ./install.sh # on each node — pulls all 10 from their registry
```
`seed-registry.sh` retags every image to `<registry>/<namespace>/...` matching the
`registry` compose override, so all 10 (4 server + 6 third-party) come from
their registry — no Docker Hub, no vendor ECR. See the "Deploy via your own internal
registry" section in `docker/CLIENT-INSTALL.md`.

**Internet-connected (alt):** if you used §4-alt (pull grant), the client doesn't need
`images.tar` — deliver the source archive + offer, give them the registry host /
namespace / tag / region, and they pull at deploy. Same `install.sh` (it skips the
offline load when there's no `images.tar`), but images come from the registry. Point
that client at [docker/CLIENT-INSTALL-CONNECTED.md](docker/CLIENT-INSTALL-CONNECTED.md)
— the connected-path client guide — instead of the air-gap `CLIENT-INSTALL.md`.

---

## 7. Upgrades & revocation

- **Upgrade:** cut a new release (§2) at the new commit → new tag, images, source
  archive. Client bumps `FORK_TAG`, `pull`, `up -d`; api migrates on start. Give them
  the new source archive (Corresponding Source for the new version) and keep the
  ledger row.
- **Revoke access:** remove the client account from the ECR repository policies (§4).
  Already-pulled images keep running until they redeploy; that's expected.

---

## AGPL compliance checklist (per delivery)

- [ ] Images built **from source** at the tagged commit (not the mirror).
- [ ] `WRITTEN_OFFER.txt` + source archive + `.sha256` delivered **with** the deployment.
- [ ] `LICENSE` (AGPL-3.0) present in the archive (it is — unmodified).
- [ ] No proprietary app code in the AGPL server (SDK/API boundary intact).
- [ ] `BYOC_LEDGER.md` row committed (who got which tag/commit, when).
- [ ] Commercial license for our app papered separately (counsel) — AGPL governs only
      the sandbox server.

---

## Troubleshooting (failures we actually hit)

| Symptom | Cause | Fix |
|---|---|---|
| `build-push` "Missing ECR repositories" (they exist) | authed to wrong AWS account | `aws sts get-caller-identity`; auth to the registry's account |
| `build-push` "working tree is dirty" | not on the tag / local edits | `git checkout byoc/<client>/<date>-<sha>` |
| runner build: `undefined: Bitmap` | computer-use native build missing X11/CGO libs | fixed — build-push builds it via `hack/computer-use/Dockerfile` |
| build: `failed to calculate checksum ... go.work.sum` | `go.work.sum` not generated | fixed — build-push generates it in a golang container |
| api: `ENOTFOUND dex` / crash-loop | eager boot dep missing (dex/minio/otel/runner) | start the named dependency; api needs all of them |
| api: `SELF_SIGNED_CERT_IN_CHAIN` | Postgres TLS CA not trusted | mount CA at `docker/certs/rds-ca-bundle.pem` or `DB_TLS_ENABLED=false` |
| dashboard login loops (HTTP-IP) | dex issuer/redirectURIs not the real host | fix `docker/dex/config.ec2.yaml` to match `PUBLIC_OIDC_DOMAIN` |
| sandbox create hangs/fails | host missing `mount-s3` / `/dev/fuse` | install mountpoint-s3; ensure `/dev/fuse` |
