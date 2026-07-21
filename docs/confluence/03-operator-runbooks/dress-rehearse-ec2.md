---
title: Dress-rehearse on EC2
labels: [byoc, operator]
---

> Source: generated from `docs/confluence/03-operator-runbooks/dress-rehearse-ec2.md`. Ported from `BYOC-DELIVERY.md` §5. Edit in git, not in Confluence.

# Dress-rehearse on EC2

Do this **before every first client deploy**. Mimic the client exactly: start from a
**fresh host**, use **only the delivered artifacts** (source archive + image pull),
**their-style datastores** (throwaway, not our prod), and finish with a **sandbox
functional test**.

## 1. Bootstrap an empty EC2 (Ubuntu)

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

The host also needs **ECR pull access** to the registry from
**[Build & push server images to ECR (OIDC)](build-push-images)** /
**[Grant a client ECR pull](grant-client-pull)** (instance role, or `aws configure` with
creds that can pull).

## 2. Throwaway datastores (simulate the client's managed Postgres/Redis)

```bash
docker network create actian-net
docker run -d --name pg --network actian-net -e POSTGRES_USER=daytona \
  -e POSTGRES_PASSWORD=rehearsal -e POSTGRES_DB=daytona postgres:18
docker run -d --name redis --network actian-net redis:7
```

## 3. Receive artifacts as the client would (no clone)

```bash
mkdir ~/rehearsal && cd ~/rehearsal
# copy in the delivered bundle (scp), OR regenerate from the tag if this host has the repo:
#   git -C <repo> archive --format=tar.gz --prefix="daytona-<sha>/" \
#     -o ~/rehearsal/daytona-src-<client>-<sha>.tar.gz byoc/<client>/<date>-<sha>
sha256sum -c daytona-src-<client>-<sha>.tar.gz.sha256
tar xzf daytona-src-<client>-<sha>.tar.gz
cd daytona-<sha>
```

## 4. Configure + bring up

Follow `docker/CLIENT-INSTALL.md` from step 2: `docker login`, fill `docker/.env`
(`FORK_TAG=byoc-<client>-...`, `DB_HOST=pg`, `REDIS_HOST=redis`, TLS off, `EC2_HOST`),
generate the dex IP config, and:

```bash
docker compose --env-file docker/.env \
  -f docker/docker-compose.yaml \
  -f docker/docker-compose.ec2-http.override.yaml \
  --network actian-net up -d      # or attach pg/redis to the daytona network
```

(Datastores + stack must share a network. If pg/redis are on `actian-net`, put the stack
there too, or publish pg/redis on host ports and point `DB_HOST`/`REDIS_HOST` at the host
IP.)

## 5. Verify — boot AND a real sandbox

Wait for `🚀 Daytona API is running`, then run the acceptance test in
`docker/CLIENT-INSTALL.md` (create a sandbox, exec, delete). That exercises runner +
ssh-gateway + proxy on the delivered images — the real proof.

## 6. Tear down

```bash
docker compose ... down
docker rm -f pg redis && docker network rm actian-net
```

## How the rehearsal legitimately differs from the client

Datastores (throwaway vs their managed) and access (HTTP-IP vs their HTTPS-domain).
Images, compose, dex, boot chain, and sandbox lifecycle are identical. Sandbox port
previews (wildcard subdomains) are the one thing untested over IP.
