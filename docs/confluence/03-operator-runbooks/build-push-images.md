---
title: Build & push server images to ECR (OIDC)
labels: [byoc, operator]
---

> Source: generated from `docs/confluence/03-operator-runbooks/build-push-images.md`. Ported from `BYOC-DELIVERY.md` §3 + `.github/workflows/dev-ecr-oidc.yml`. Edit in git, not in Confluence.

# Build & push server images to ECR (OIDC)

The 4 Daytona service images (`api`, `proxy`, `runner`, `ssh-gateway`) MUST be built
**from source** at the tagged commit — not the `hub-*` mirror (raw upstream, root, no
AGPL provenance). Into the **platform-core account** (`120354378950`) they land via the
GitHub Actions workflow `dev-ecr-oidc.yml`, which builds from source and pushes via OIDC.

> **Platform-core is OIDC-only — no local push keys.** A laptop cannot `docker push` to
> `120354378950`. For an account you *do* hold push creds for, run `build-push.sh`
> directly instead (see the alternative at the bottom).

The image tag comes from the repo-root `VERSION` file (single source of truth), which
must be semver `MAJOR.MINOR.PATCH` — the cluster's Kyverno policy rejects `:latest` and
commit-hash-only tags.

## 1. Bump VERSION

Edit the repo-root `VERSION` file to the new `MAJOR.MINOR.PATCH` and commit it. The
workflow reads it and tags each image `:<VERSION>` and `:<VERSION>-<7-char-sha>`.

## 2. Run the workflow from main

```bash
gh workflow run dev-ecr-oidc.yml --ref main
```

- **To PUSH, run from `main`** (deploy role). Other branches assume the read-only plan
  role and build only, which makes it safe to test from a branch.
- A manual run can override the tag with the `image_version` input (must be
  `MAJOR.MINOR.PATCH`); leave blank to use `VERSION`.

## 3. Watch it

```bash
gh run watch
```

The job builds the 4 services as a matrix (`fail-fast: false`, so one service failing
does not cancel the others), pushes on `main`, and writes each image's immutable digest
to the run's step summary. Those digests are what
`docker/docker-compose.registry.override.yaml` pins.

## The OIDC-onboarding gotcha

The workflow is **partially onboarded**. The `cicd` GitHub Environment exists (item 1
done), but do not expect a green push until:

2. IAM trust on `github-actions-cicd-ideaboxai-{deploy,plan}` is extended to
   `repo:ideaboxai/daytona`.
3. Those roles are permitted to push to `ideaboxai-platform-core/*`. Every other repo
   pushes to `ideaboxai-dev/*`, so if the policy is resource-scoped by prefix this
   namespace is **not** covered and pushes fail with `AccessDenied` even once trust is
   extended — the failure that looks like "trust is broken" but isn't. Worth checking
   explicitly.
4. `daytona` is granted access to the `ideaboxai-deploy-small` runner group.

## Architecture note

Single-arch, matching the runner (amd64). The EC2 deploy target must match — an amd64
image will not run on Graviton. For arm64, add a matrix leg pinned to an arm64
self-hosted runner and merge the two manifests with `docker buildx imagetools create`.

## Shipping a byoc-* tag through the workflow

The workflow's semver check rejects `byoc-*` tags today. To ship a `byoc-*` tag through
it, the workflow must build from the byoc tag — adapt the workflow, or push from a host
that has a role in this account.

## Alternative: an account you hold push creds for (e.g. `304038454586`/`ideaboxai`)

Run `build-push.sh` directly, **from the tagged commit** so the image matches the source
you hand over:

```bash
git fetch origin --tags && git checkout byoc/<client>/<date>-<sha>
aws ecr get-login-password --region us-east-1 \
  | docker login --username AWS --password-stdin <ACCT>.dkr.ecr.us-east-1.amazonaws.com
TAG=byoc/<client>/<date>-<sha> \
FORK_REGISTRY=<ACCT>.dkr.ecr.us-east-1.amazonaws.com/<namespace> \
  ./scripts/fork/build-push.sh
```

`build-push.sh` sanitizes the tag's `/` → `-` (Docker tags forbid `/`), so images push as
`byoc-<client>-<date>-<sha>`.

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
