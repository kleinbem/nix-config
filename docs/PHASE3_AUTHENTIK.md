# Phase 3 — Authentik IdP (deferred)

Scaffold is in place; **do not enable yet**. Enable when Phase 3 (Matrix federation
or sigstore OIDC for personas) actually requires an identity provider.

## When to flip this on

You'll know it's time when one of these is true:

- You're standing up Matrix/Synapse and want federation across the persona-fleet
- You're moving signing to sigstore (gitsign) and need per-persona OIDC subjects
- You want a single SSO surface for personas across Stalwart, Matrix, Jitsi,
  Nextcloud, etc.
- The TEAM.html page evolves into something that needs auth

Until any of those is true: stay on Authelia (current SSO at the edge for
code/home apps) + the markdown TEAM directory.

## Enabling (when ready)

### 1. Generate secrets

```bash
openssl rand -hex 32 > /tmp/authentik-secret-key
openssl rand -base64 24 > /tmp/authentik-postgres-pwd
openssl rand -base64 24 > /tmp/authentik-admin-pwd
openssl rand -hex 32 > /tmp/authentik-api-token

# Encrypt into sops
cd ~/Develop/github.com/kleinbem/nix/nix-secrets
for s in secret-key postgres-pwd admin-pwd api-token; do
  cp /tmp/authentik-$s authentik/$s
  sops --encrypt --in-place authentik/$s
done
rm /tmp/authentik-*
```

### 2. Add inventory + sops template

`nix-config/inventory.nix` — register the auth node so Caddy can reverse-proxy:

```nix
authentik = {
  ip = "10.85.46.150";   # next free
  port = 9000;
  externalPort = 443;
  domain = "auth.kleinbem.dev";
  meta = {
    name = "Authentik";
    category = "Security";
    icon = "🔐";
    description = "Identity provider for personas (OIDC / SAML).";
  };
};
```

`nix-config/hosts/nixos-nvme/secrets.nix` — sops templates that
materialise the secret files inside the container:

```nix
sops.secrets."authentik/secret-key" = { sopsFile = ../../../nix-secrets/authentik/secret-key; };
# … repeat for postgres-pwd, admin-pwd, api-token
```

### 3. Enable in host

```nix
my.containers.authentik = {
  enable = true;
  ip = "10.85.46.150";
  hostDataDir = "/var/lib/containers/authentik";
  domain = "auth.kleinbem.dev";
  secretKeyFile = config.sops.secrets."authentik/secret-key".path;
  postgresPasswordFile = config.sops.secrets."authentik/postgres-pwd".path;
  bootstrapAdminPasswordFile = config.sops.secrets."authentik/admin-pwd".path;
  bootstrapApiTokenFile = config.sops.secrets."authentik/api-token".path;
};
```

Run `just apply`. Browse https://auth.kleinbem.dev — log in as `akadmin`
with the password you generated above.

### 4. Sync personas into Authentik via Terraform

Add to `nix/terraform/authentik.tf`:

```hcl
terraform {
  required_providers {
    authentik = {
      source  = "goauthentik/authentik"
      version = "~> 2024.10"
    }
  }
}

provider "authentik" {
  url   = "https://auth.kleinbem.dev"
  token = var.authentik_api_token
}

resource "authentik_user" "persona" {
  for_each   = local.personas
  username   = each.key
  name       = each.value.full-name
  email      = each.value.email
  is_active  = lookup(each.value.state, "status", "active") == "active"

  attributes = jsonencode({
    origin     = each.value.origin
    timezone   = each.value.timezone
    role_tags  = each.value.role-tags
    tool       = each.value.tool
    model      = each.value.model
  })
}

resource "authentik_group" "role" {
  for_each = toset(flatten([for p in values(local.personas) : p.role-tags]))
  name     = each.value
}
```

Then `just personas::tf-apply` provisions every persona in `personas.nix` as
an Authentik user with matching attributes + group memberships.

### 5. Custom-code retirement

Once Authentik is sourcing user data, these become vestigial:

- `lib/personas.nix.teamMarkdown` — Authentik's user list UI replaces it
- `lib/personas.nix.assertUniqueEmails` — Authentik enforces at DB level
- `nix-config/docs/TEAM.{md,html}` regeneration — Authentik UI is the directory

Keep `personas.nix` itself (source of truth) and `lib/personas.nix.author`
(used by `jj::as` for commit author strings). Drop the rest.

## What Authentik will replace from the current setup

| Today's mechanism | Replaced by |
|---|---|
| `lib/personas.nix.teamMarkdown` → TEAM.html | Authentik web UI user list |
| `lib/personas.nix.assertUniqueEmails` | Postgres unique constraint |
| Per-persona OIDC subject in `personas.nix` | Authentik issues actual OIDC tokens |
| Manual mailbox creation via stalwart-cli | Authentik → Stalwart user provisioning hook |
| Matrix user creation (Phase 3) | Authentik → Synapse SSO |
| Cloudflare Access app per persona | Authentik → CF Access OIDC provider |

The pieces NOT replaced:
- `personas.nix` and `personas-state.nix` stay as the **source of truth** — Terraform
  reads them and reflects into Authentik (one-way sync, manifest-first).
- `users/<name>/voice.md` files stay — they're system prompts, not user records.
- `nix-config/scripts/persona-scaffold.sh` stays but gets a Terraform step added.
