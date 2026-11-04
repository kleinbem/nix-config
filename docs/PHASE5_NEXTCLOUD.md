# Phase 5 — Nextcloud (collaboration)

The scaffold is in place; it is **not enabled**. It sits dormant in the
preset registry until persona count or workflow needs justify flipping
it on.

> The Phase 4 Odoo HRIS scaffold was dropped on 2026-10-02 in favour of
> **Twenty** (CRM / people directory) + **Invoice Ninja** (invoicing).

## When to flip it on

| You start needing… | Enable |
|---|---|
| Real OIDC token issuance for personas | Authentik (Phase 3) |
| A shared calendar / contacts source of truth | Nextcloud (CalDAV/CardDAV) |
| Per-persona file storage, notes, talk/video | Nextcloud |

Rule of thumb: at **5 personas** it doesn't earn its keep. At **50+**,
Nextcloud Talk's group-call ability starts to matter.

## Integration topology

```
            Authentik (OIDC issuer)
                │
        ┌───────┴───────┐
        ▼               ▼
    Nextcloud    Other (Matrix, etc.)
        │
        ▼
 Calendar / Files / Talk (source of truth)
```

**Source-of-truth rules** (avoid double-writes):

- **Identity**: Authentik
- **Files / documents / notes / video**: Nextcloud
- **Calendar**: Nextcloud
- **Mail**: Stalwart

## Enabling Nextcloud

### 1. Secrets

```bash
openssl rand -base64 24 > /tmp/nc-db
openssl rand -base64 24 > /tmp/nc-admin

cd ~/Develop/github.com/kleinbem/nix/nix-secrets
mkdir -p nextcloud
mv /tmp/nc-db nextcloud/db-password
mv /tmp/nc-admin nextcloud/admin-password
sops --encrypt --in-place nextcloud/db-password
sops --encrypt --in-place nextcloud/admin-password
```

### 2. Host config

```nix
my.containers.nextcloud = {
  enable = true;
  ip = "10.85.46.152";
  hostDataDir = "/var/lib/containers/nextcloud";
  domain = "cloud.kleinbem.dev";
  dbPasswordFile = config.sops.secrets."nextcloud/db-password".path;
  adminPasswordFile = config.sops.secrets."nextcloud/admin-password".path;
  oidcUpstream = "https://auth.kleinbem.dev/application/o/nextcloud/";
};
```

### 3. Configure SSO via Authentik

1. In Authentik, create a Nextcloud OIDC Provider + Application.
2. In Nextcloud, install + enable the `user_oidc` app.
3. Configure the OIDC connector with the Authentik discovery URL.
4. Now personas log in via Authentik; their email/name/groups
   sync automatically.

## Combined footprint (when enabled)

| Service | RAM | Disk |
|---|---|---|
| Stalwart | 200 MB | small |
| Authentik (+ PG + Redis) | 500 MB | 500 MB |
| Nextcloud (+ Postgres + Redis) | 1.5 GB | grows with files |
| **Total** | **~2.2 GB** | grows with files |

## Why this stack and not alternatives

| Alternative considered | Why not |
|---|---|
| **Mattermost** instead of Talk | Strong tool but adds another service; Nextcloud Talk piggybacks on existing stack |
| **Joplin / Logseq** instead of Notes | Personal-scale tools; Nextcloud Notes is collaboration-aware |
| **Gitea Issues** for tasks | Different shape (code-issues vs general tasks); Nextcloud Deck fits "kanban for the team" better |
