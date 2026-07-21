---
title: Grant a client ECR pull
labels: [byoc, operator, connected]
---

> Source: generated from `docs/confluence/03-operator-runbooks/grant-client-pull.md`. Ported from `BYOC-DELIVERY.md` §4-alt. Edit in git, not in Confluence.

# Grant a client ECR pull

For a **connected** client that pulls from our ECR instead of loading `images.tar` — the
model actian uses (their nodes pull from our ECR, same as our app). Two sub-cases, by
whether the client's network can reach Docker Hub.

## If the client canNOT reach Docker Hub (e.g. actian)

Mirror the 6 third-party into our ECR too, so all 10 live there:

```bash
FORK_REGISTRY=<host>/<namespace> ./scripts/fork/mirror-thirdparty.sh   # 6 third-party -> our ECR
```

This pushes to the repos `dex`, `docker-registry-ui`, `registry`,
`jaegertracing/all-in-one`, `minio`, `opentelemetry-collector-contrib` — matching
`docker-compose.registry.override.yaml`. The client deploys with `IMAGE_SOURCE=registry`
(adds that override) so **all 10** pull from `FORK_REGISTRY`. Grant pull on **all 10**
repos below (add the 6 third-party repo names to the loop). See
**[Mirror third-party images to ECR](mirror-thirdparty)**.

## Grant cross-account pull

Revocable; never push. For the actian case list all 10 repos; for a Hub-connected client,
just the 4 `daytona-*`:

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

For a **Hub-connected** client, drop the six third-party repos from the loop and grant
only the 4 `daytona-*`.

Hand the client `docker/CLIENT-INSTALL-CONNECTED.md` + the registry host / namespace /
tag / region. (To push into the client's OWN ECR instead, point `FORK_REGISTRY` at theirs
in **[Build & push server images to ECR (OIDC)](build-push-images)** and skip the grant.)

## Revoking

Remove the client account from the repository policies — see
**[Upgrades & revocation](upgrades-revocation)**. Already-pulled images keep running until
they redeploy; that's expected.
