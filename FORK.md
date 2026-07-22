# Daytona — self-hosted fork (maintenance guide)

## Why this fork exists

Daytona announced on **2026-06-11** that core development moves to a **private** repo.
The open-source `daytonaio/daytona` repo **stays public but is frozen and unmaintained** —
no more updates, fixes, or releases
([announcement](https://www.daytona.io/dotfiles/updates/daytona-is-going-closed-source)).

We self-host Daytona on EC2. **Legally we are fine indefinitely:** the code is **AGPL-3.0**
(`LICENSE`) and AGPL grants are irrevocable — Daytona cannot revoke the license on code already
released. We may run, modify, and fork it forever.

- **AGPL obligation:** only if we run a _modified_ version and offer it _over a network to third
  parties_ must we publish our source. Internal-only use carries no publication obligation.
- The risks are **operational, not legal**: no upstream security patches, and Docker Hub images /
  upstream git could disappear. This fork removes those dependencies.

## Fork provenance

| Field | Value |
|-------|-------|
| Forked from | `github.com/daytonaio/daytona` |
| Fork point commit | `f7f6b7f57ba832e32457da31f7df256ce968bc72` |
| Fork point date | 2026-04-29 |
| Upstream status | frozen / unmaintained as of 2026-06-11 |
| License | AGPL-3.0 (`LICENSE`) — unchanged, irrevocable |

## Architecture note (why we're self-sufficient)

The stack is fully self-contained — no external license server or phone-home in the compose:
self-hosted container registry (`registry:6000`), self-hosted auth (`dexidp/dex`), `minio`,
`postgres`, `redis`. Auth does **not** depend on Daytona's servers. The only external dependency
was **prebuilt Docker Hub images** `daytonaio/daytona-{api,proxy,runner,ssh-gateway}` — which this
fork replaces with images we build from source.

---

## Runbook

### 1. Own the source (one-time)

```bash
FORK_REMOTE=git@github.com:your-org/daytona.git ./scripts/fork/mirror-upstream.sh
```

Pushes a full mirror (all branches/tags/history) to our git host, repoints `origin` -> our fork,
and keeps `upstream` as a **read-only** remote for final cherry-picks. Before upstream goes quiet,
pull any commits landed after our fork point:

```bash
git fetch upstream && git log --oneline HEAD..upstream/main
# cherry-pick anything relevant, then push to our fork
```

### 2. Build our own images + pin them (removes Docker Hub dependency)

```bash
# Build the 4 services from source, push to our registry, capture digests:
FORK_REGISTRY=123456789.dkr.ecr.us-east-1.amazonaws.com ./scripts/fork/build-push.sh
# -> dist/fork-image-digests-<tag>.txt
```

Then create the live override from the template and paste in the digests:

```bash
cp docker/docker-compose.registry.override.yaml.example docker/docker-compose.registry.override.yaml
# fill in @sha256 digests for our 4 services AND the previously-unpinned third-party
# images (redis, registry-ui, maildev, minio). Set FORK_REGISTRY + FORK_TAG in docker/.env.
```

Deploy with the override applied **last** so it wins:

```bash
docker compose --env-file docker/.env \
  -f docker/docker-compose.yaml \
  -f docker/docker-compose.registry.override.yaml up -d
```

> Do **not** edit `docker/docker-compose.yaml` directly with our registry — keep the fork changes
> isolated in the override so upstream compose stays diffable.

### 3. Rebuild + redeploy (recurring)

```bash
git pull                                   # our fork
FORK_REGISTRY=... ./scripts/fork/build-push.sh
# update digests in docker/docker-compose.registry.override.yaml, then:
docker compose --env-file docker/.env -f docker/docker-compose.yaml \
  -f docker/docker-compose.registry.override.yaml up -d
```

### 4. Security self-maintenance (the real reason we own the fork)

- **Dependency updates:** `.github/dependabot.yml` now covers `gomod` + `npm` (not just
  github-actions) — security + minor/patch groups. Review and merge these on our fork.
- **Image scanning:** scan built images before deploy, e.g.
  `trivy image ${FORK_REGISTRY}/daytona-runner:<tag>` (or Grype). Triage before rollout.
- **Isolation boundary:** the `runner` service + sandbox images (`images/sandbox/Dockerfile`,
  `images/sandbox-slim/Dockerfile`) are where untrusted code runs. Keep the host kernel, container
  runtime, and these images patched. Since upstream hardening has stopped, consider stronger
  isolation (gVisor / Kata / Firecracker) for the runner.

### 5. Secrets

`docker/.env` is gitignored and was **never committed** — verified, no rotation needed. For EC2
durability, source these from AWS SSM Parameter Store / Secrets Manager rather than a file on disk.

---

## BYOC — conveying Daytona to a client (AGPL-3.0)

Deploying the Daytona **server** onto a client's servers is _conveying_ under
AGPL-3.0: that client must receive the complete Corresponding Source of the exact
version running. This is separate from our SaaS use and is the one hard AGPL
obligation for BYOC.

Scope: only the AGPL **server** is affected. Our application is proprietary and
uses the **Apache-2.0** Daytona SDK (`libs/sdk-python` et al.) over the network —
permissive, no copyleft reach — so it is **not** part of this handoff. Keep that
boundary: integrate via the SDK/API, never by welding app logic into the server.

**Full runbooks:** the end-to-end operator steps (cut → build → grant → rehearse →
deliver) are in [`BYOC-DELIVERY.md`](BYOC-DELIVERY.md); the client-facing deploy guide
is [`docker/CLIENT-INSTALL.md`](docker/CLIENT-INSTALL.md) (ships inside the source
archive). This section is the summary.

One command per client deploy:

```bash
CLIENT=acmecorp \
CLIENT_REGISTRY=<acct>.dkr.ecr.<region>.amazonaws.com \
./scripts/fork/byoc-release.sh
```

It (idempotently): cuts an immutable tag `byoc/<client>/<date>-<sha>`, bundles the
source of that tag (`git archive`) with a `sha256`, renders `WRITTEN_OFFER.txt`
from `scripts/fork/templates/WRITTEN_OFFER.template.txt`, builds + pushes the
server images from that exact tag, and appends a row to `BYOC_LEDGER.md`.

Deliver to the client, alongside the deployment:

```
dist/byoc/<client>/<date>-<sha>/daytona-src-<client>-<sha>.tar.gz   # Corresponding Source
dist/byoc/<client>/<date>-<sha>/daytona-src-<client>-<sha>.tar.gz.sha256
dist/byoc/<client>/<date>-<sha>/WRITTEN_OFFER.txt                   # AGPL §6 notice
```

`BYOC_LEDGER.md` is your compliance paper trail — commit it after each run.
`dist/` is gitignored, so the client source bundles never enter git.

### Granting the client pull access (our images stay in our registry)

We keep the images in our ECR and grant the client's AWS account cross-account
**pull** — they never get push, and we can revoke. Attach a repository policy to
each of the four `daytona-*` repos (replace the client account id):

```bash
for repo in daytona-api daytona-proxy daytona-runner daytona-ssh-gateway; do
  aws ecr set-repository-policy --region <region> \
    --repository-name <namespace>/$repo \
    --policy-text '{
      "Version": "2012-10-17",
      "Statement": [{
        "Sid": "AllowClientPull",
        "Effect": "Allow",
        "Principal": { "AWS": "arn:aws:iam::<CLIENT_ACCOUNT_ID>:root" },
        "Action": [
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:BatchCheckLayerAvailability"
        ]
      }]
    }'
done
```

The client then authenticates with **their own** creds and pulls from our registry
host (their `docker login` token identifies their principal; the repo policy above
authorizes it). Their steps are in `docker/CLIENT-INSTALL.md`, which ships inside the
source archive. Give them: the registry host, the namespace, and the image tag
(`byoc-<client>-<date>-<sha>` — note `build-push.sh` sanitizes the `/` in the git
tag to `-` for the Docker tag).

> The client inherits AGPL rights on the **server** (use/modify/redistribute) —
> that is expected and cannot be restricted. Your proprietary app is unaffected.
> Paper the commercial terms with a lawyer; the source-handoff above satisfies the
> license mechanics.

---

## Verification / DR drill

1. **Build from source works:**
   `docker compose --env-file docker/.env -f docker/docker-compose.yaml -f docker/docker-compose.build.override.yaml build`
   completes for `api proxy runner ssh-gateway`.
2. **Runs on our images only:** bring the stack up on a host with no cached `daytonaio/*` images →
   all services healthy (proves no Docker Hub dependency).
3. **Functional smoke test:** create a sandbox via the CLI/API, run code, exec/ssh in, tear down —
   exercises runner + ssh-gateway + proxy on our-built images.
4. **Pins immutable:** re-pull by digest returns the identical image; no `:latest`/`:main`/untagged
   image remains in the effective config (`docker compose ... config | grep image:`).
5. **Full DR:** on a fresh EC2 instance — clone our mirror + pull our registry images + apply env
   from secrets manager → stack comes up with **zero** dependency on daytona.io or Docker Hub
   `daytonaio/*`.
