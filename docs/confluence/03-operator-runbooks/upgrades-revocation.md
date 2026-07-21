---
title: Upgrades & revocation
labels: [byoc, operator]
---

> Source: generated from `docs/confluence/03-operator-runbooks/upgrades-revocation.md`. Ported from `BYOC-DELIVERY.md` §7. Edit in git, not in Confluence.

# Upgrades & revocation

## Upgrade

Cut a new release (**[Cut a release](cut-a-release)**) at the new commit → new tag,
images, source archive. The client bumps `FORK_TAG`, `pull`, `up -d`; the api migrates on
start. Give them the new source archive (Corresponding Source for the new version) and
keep the ledger row.

## Revoke access

Remove the client account from the ECR repository policies (see
**[Grant a client ECR pull](grant-client-pull)**). Already-pulled images keep running
until they redeploy; that's expected.
