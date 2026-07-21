---
title: Operate, backup & upgrade
labels: [byoc, client]
---

> Source: generated from `docs/confluence/06-verify-operate/operate-backup-upgrade.md`. Ported from the "Operate & maintain" section of `docker/CLIENT-INSTALL.md` and §7 of `BYOC-DELIVERY.md`. Edit in git, not in Confluence.

# Operate, backup & upgrade

Day-2 operations for a running deployment. All `docker compose` commands use the **same
`-f` file set** you brought the stack up with (base compose + the `ec2-http` override, or
your HTTPS reverse-proxy setup).

## Logs, restart, stop

- **Logs:**
  ```bash
  docker compose ... logs -f <service>
  ```
- **Restart:**
  ```bash
  docker compose ... restart <service>
  ```
- **Stop:**
  ```bash
  docker compose ... down
  ```
  This removes the containers only — your Postgres/Redis/MinIO data persists in their own
  stores/volumes.

## Back up

Your **Postgres database (`daytona`)** and the **MinIO/S3 bucket** hold all state.
Snapshot them on your normal schedule; **the containers are stateless**. There is nothing
else to back up on the host.

## Upgrade to a new version

The vendor gives you a new image tag (and a new source archive).

1. Set the new `FORK_TAG` in `docker/.env`.
2. Pull and bring up:
   ```bash
   docker compose ... pull && docker compose ... up -d
   ```

The api runs any new DB migrations on start. **Keep each source archive you receive** — it
is the AGPL Corresponding Source for that version.

## Rotate the login

Replace the `dev@daytona.io` static password in `docker/dex/config.*.yaml` (bcrypt hash),
or wire dex to your own IdP. Change it for anything beyond a first test.

---

Before and after any of the above, re-run the
**[acceptance test](acceptance-test)** to confirm the deployment still creates sandboxes.
When something breaks, see **[Troubleshooting](../07-troubleshooting)**.
