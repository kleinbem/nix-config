# Phase 1 — Stalwart Mail + First Persona Mailbox

Scaffold for the persona-fleet's Phase 1, per the architecture in
[persona-fleet memory](../../.agent/knowledge/) and `nix-config/personas.nix`.

## What the scaffold gives you

- `nix-presets/containers/stalwart.nix` — a Stalwart Mail Server container
  preset using the Switchboard pattern (`my.containers.stalwart.*`).
- Reads `nix-config/personas.nix` and declares one mailbox per persona.
- Supports outbound relay via AWS SES (or any SMTP provider with a
  user/pass file).
- Ports 25/143/587/8080 opened.
- DKIM signing skeleton (Stalwart auto-generates keys on first start).

## Manual steps (in order)

### 1. DNS records on `kleinbem.dev`

Add via Terraform (in `github-config` repo or wherever your Cloudflare DNS
lives). Replace `<host-ip>` with the public-facing ingress IP for mail.

```
MX     kleinbem.dev.                         10 mail.kleinbem.dev.
A      mail.kleinbem.dev.                       <host-ip>
TXT    kleinbem.dev.                         "v=spf1 include:amazonses.com -all"
TXT    _dmarc.kleinbem.dev.                  "v=DMARC1; p=reject; rua=mailto:dmarc@kleinbem.dev; aspf=s; adkim=s"
TXT    _mta-sts.kleinbem.dev.                "v=STSv1; id=20260616"
# DKIM:
# Stalwart generates the key on first start. SSH into the container and:
#   journalctl -u stalwart-mail | grep dkim
# then publish the public key at:
TXT    default._domainkey.kleinbem.dev.      "v=DKIM1; k=rsa; p=<base64-pubkey>"
```

### 2. AWS SES setup

```bash
# Verify the domain in SES (eu-central-1 or your preferred region):
aws sesv2 create-email-identity --email-identity kleinbem.dev --region eu-central-1

# Add the SES-provided DKIM CNAMEs (3 records) to your DNS.
# Then create an IAM user with ses:SendRawEmail permission.
# Generate SMTP credentials from the AWS access key:
#   https://docs.aws.amazon.com/ses/latest/dg/smtp-credentials.html
```

### 3. Store credentials in sops

```yaml
# nix-secrets/secrets.yaml — add under `stalwart`:
stalwart:
  ses-smtp-credentials: |
    username=AKIA....
    password=BHo....
  admin-password-hash: '$6$rounds=...'  # mkpasswd -m sha-512 <admin-pwd>
```

### 4. Enable the container on a host

In `nix-config/hosts/<host>/containers.nix`:

```nix
my.containers.stalwart = {
  enable = true;
  ip = "10.85.46.140";                                # next free IP on cbr0
  hostDataDir = "/var/lib/containers/stalwart";       # ZFS dataset preferred
  domain = "kleinbem.dev";
  relaySecretFile = config.sops.secrets."stalwart/ses-smtp-credentials".path;
  adminPasswordFile = config.sops.secrets."stalwart/admin-password-hash".path;
};
```

Run `just apply`.

### 5. Set initial mailbox passwords

After Stalwart starts, set each persona's mailbox password via the admin CLI.
Resolve `<email>` and `<full-name>` from `nix-secrets/personas-contact.nix`
(the private contact file) for each persona key in `nix-config/personas.nix`:

```bash
sudo machinectl shell stalwart /run/current-system/sw/bin/bash
stalwart-cli account add <persona-email> "<persona-full-name>"
# Loop over keys in personas.nix; emails come from the private contact file.
```

### 6. Generate a persona's signing key

```bash
mkdir -p ~/Develop/github.com/kleinbem/nix/nix-secrets/personas/<name>
ssh-keygen -t ed25519 -C "<persona-email>" -N "" \
  -f ~/Develop/github.com/kleinbem/nix/nix-secrets/personas/<name>/id_ed25519

# Encrypt private key with sops
cd ~/Develop/github.com/kleinbem/nix/nix-secrets
sops --encrypt --in-place personas/<name>/id_ed25519

# Paste the .pub contents into nix-config/modules/nixos/keys.nix:
#   ssh.personas.<name> = "ssh-ed25519 AAAA...";
```

### 7. First persona commit

```bash
# In any sub-flake (e.g. nix-presets to add a new container):
just jj::as <name> save-all "feat(presets): smoke-test commit as <name>"
just jj::push-all
```

The commit should land on GitHub with:
- Author header set from the persona's contact entry (`<full-name> <email>`)
- A "verified" signature (after the pubkey is uploaded to GitHub as a Signing key)
- ✅ Phase 1 complete.

## What's NOT in scope here

- Cloudflare Access OIDC apps per persona (Phase 3 — when persona-tool runtime needs SSO)
- Matrix/Synapse user provisioning (Phase 3)
- Per-persona Qdrant collections (Phase 4)
- Jitsi sprint calls (Phase 5)
- AWS SES → other providers (Brevo/MailerSend/Mailgun) — relay config is generic enough to swap

## Cost at flat-scale

- Stalwart: free, one-time container resource (~200 MB RAM)
- AWS SES: $0.10 / 1000 outbound emails — for 5 personas this is sub-cent/year
- DNS: existing Cloudflare zone, free
- **Adding the 6th–300th persona**: edit personas.nix, regenerate, set initial mailbox password. ~2 minutes per persona, no recurring cost.
