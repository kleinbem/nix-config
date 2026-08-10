# Phase 4 + 5 — Odoo (HRIS) + Nextcloud (collaboration)

Both scaffolds are in place; **neither enabled**. They sit dormant
in the preset registry until persona count or workflow needs justify
flipping them on.

## When to flip what on

| You start needing… | Enable |
|---|---|
| Real OIDC token issuance for personas | Authentik (Phase 3) |
| A calendar that's the source of truth for who's on leave | Nextcloud (CalDAV) |
| An HR view with org chart, leave approval, employee records | Odoo (Phase 4) |
| Per-persona file storage, notes, talk/video | Nextcloud (Phase 5) |

Rule of thumb: at **5 personas**, neither earns its keep. At **20+**,
Odoo's directory + leave calendar become genuinely useful. At **50+**,
Nextcloud Talk's group-call ability starts to matter.

## Integration topology

```
            Authentik (OIDC issuer)
                │
   ┌────────────┼────────────┐
   ▼            ▼            ▼
 Odoo      Nextcloud    Other (Matrix, etc.)
   │            │
   │            ▼
   │   Calendar / Files / Talk (source of truth)
   ▼
 HR records (employees, leave, org)
   ▲
   │  CalDAV pull (Odoo reads Nextcloud calendars)
   └──────── Nextcloud
```

**Source-of-truth rules** (avoid double-writes):

- **Identity**: Authentik
- **Files / documents / notes / video**: Nextcloud
- **Calendar / contacts**: Nextcloud (Odoo subscribes)
- **HR records / employee data / org chart**: Odoo
- **Mail**: Stalwart

## Enabling Odoo

### 1. Secrets

```bash
openssl rand -base64 24 > /tmp/odoo-db
openssl rand -base64 24 > /tmp/odoo-admin

cd ~/Develop/github.com/kleinbem/nix/nix-secrets
mkdir -p odoo
mv /tmp/odoo-db odoo/db-password
mv /tmp/odoo-admin odoo/admin-password
sops --encrypt --in-place odoo/db-password
sops --encrypt --in-place odoo/admin-password
```

### 2. Host config (e.g. `nix-config/hosts/nixos-nvme/containers.nix`)

```nix
my.containers.odoo = {
  enable = true;
  ip = "10.85.46.151";              # next free
  hostDataDir = "/var/lib/containers/odoo";
  domain = "hr.kleinbem.dev";
  dbPasswordFile = config.sops.secrets."odoo/db-password".path;
  adminPasswordFile = config.sops.secrets."odoo/admin-password".path;
  oidcUpstream = "https://auth.kleinbem.dev/application/o/odoo/"; # set after Authentik is up
};
```

Plus the sops secrets declarations in `secrets.nix`, plus an
`inventory.nix` node so Caddy reverse-proxies `hr.kleinbem.dev`.

### 3. Sync personas → Odoo employees

Once Odoo is running, populate from `personas.nix` via the
`odoorpc` library:

```bash
# scripts/sync-personas-to-odoo.sh (sketch — write when ready)
nix run nixpkgs#python3Packages.odoorpc -- - <<'PY'
import json, odoorpc
personas = json.load(open("terraform/personas.json"))
o = odoorpc.ODOO("hr.kleinbem.dev", port=443, protocol="jsonrpc+ssl")
o.login("odoo", "<admin>", "<pwd>")
Employee = o.env["hr.employee"]
for name, p in personas.items():
    Employee.create({"name": p["full-name"], "work_email": p["email"]})
PY
```

Alternative: use the community Terraform provider once it matures.

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

### 4. Configure CalDAV → Odoo

In Nextcloud's Calendar app, each persona gets a personal calendar
(auto-created). Odoo's Calendar module subscribes via CalDAV:
**Settings → Calendar → External Calendars → Add CalDAV** with
`https://cloud.kleinbem.dev/remote.php/dav/calendars/<persona>/`.

Then Odoo's Leave (`hr_holidays`) writes approved leaves back to
Nextcloud as events — one canonical view.

## Retiring custom code

Once the stack is operational:

| Today | After Phase 5 |
|---|---|
| `lib/personas.nix.teamMarkdown` | Odoo HR employee list (rich UI) |
| `docs/TEAM.html` + Caddy `staticSites` | Replaced by Odoo's directory UI |
| Hand-maintained `personas-state.nix` | Odoo's Leave model + Authentik's is_active |
| Voice files browsed in editor | Voice files synced into per-persona Nextcloud folder |

`personas.nix` (identity manifest) stays as the source of truth.
Everything else becomes a reflection — Terraform / sync scripts
keep Authentik, Odoo, and Nextcloud aligned with the manifest.

## Combined footprint (when all enabled)

| Service | RAM | Disk |
|---|---|---|
| Stalwart | 200 MB | small |
| Authentik (+ PG + Redis) | 500 MB | 500 MB |
| Odoo (+ Postgres) | 2.5 GB | 5 GB + content |
| Nextcloud (+ Postgres + Redis) | 1.5 GB | grows with files |
| **Total** | **~5 GB** | ~10 GB + content |

On `nixos-nvme` (32+ GB RAM, plenty of NVMe), comfortable.

## Why this stack and not alternatives

| Alternative considered | Why not |
|---|---|
| **ERPNext / Frappe HR** instead of Odoo | No NixOS native module; would need Docker + MariaDB |
| **Mattermost** instead of Talk | Strong tool but adds another service; Nextcloud Talk piggybacks on existing stack |
| **Joplin / Logseq** instead of Notes | Personal-scale tools; Nextcloud Notes is collaboration-aware |
| **Gitea Issues** for tasks | Different shape (code-issues vs general tasks); Nextcloud Deck fits "kanban for the team" better |

The chosen stack (Authentik + Stalwart + Odoo + Nextcloud) is what
real OSS-first organizations deploy. It's a known-good combo.
