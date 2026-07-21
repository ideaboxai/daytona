---
title: Verify & operate
labels: [byoc]
---

> Source: generated from `docs/confluence/06-verify-operate/index.md`. Ported from `docker/CLIENT-INSTALL.md` and `BYOC-DELIVERY.md`. Edit in git, not in Confluence.

# Verify & operate

Every delivery scenario ends here. **Booting is necessary but not sufficient** — confirm
a sandbox actually works, since that is what your application consumes. Then keep the
deployment running: logs, backups, and version upgrades.

- **[Acceptance test (boot + sandbox)](acceptance-test)** — confirm all services are up,
  `curl /api/health` → `200`, then create a sandbox, exec a command, delete it. This is
  the real acceptance signal.
- **[Operate, backup & upgrade](operate-backup-upgrade)** — logs / restart / stop, what
  to back up (Postgres + MinIO — the containers are stateless), how to upgrade to a new
  image tag, and how to rotate the login.

When something fails, see **[7. Troubleshooting](../07-troubleshooting)** — the failures
we actually hit, with symptom → cause → fix.
