# Secrets Management Best Practices

**Status:** Secrets encryption via sops + age
**Updated:** 2026-09-11

Guide to managing secrets securely in the kleinbem fleet using sops, age, and NixOS.

---

## Overview

The kleinbem fleet uses **sops-nix** for encrypted secrets management. Secrets do **not** live in this repo — they live in the sibling **`kleinbem-secrets`** repo, consumed here through the `nix-secrets` flake input (the input keeps its old name; it's pinned at `kleinbem-secrets` — see `flake.nix`):

- **Encryption:** age (YubiKey-backed for Martin's own key, ssh-derived or TPM-bound per NixOS host)
- **Integration:** sops (human-editable encrypted YAML)
- **Policy:** `kleinbem-secrets/.sops.yaml` — who can decrypt what, scoped per path
- **Secret files:** `kleinbem-secrets/nix/shared.yaml` (fleet-wide default), `kleinbem-secrets/nix/per-host/<host>.yaml`, `kleinbem-secrets/nix/per-container/<name>.yaml`

```
plaintext secret → age encryption → sops file (kleinbem-secrets) → git commit → deploy
                                     ↑
                              nix eval + activation (sops-install-secrets)
```

---

## Quick Start

### 1. Access Existing Secrets (Development)

```bash
cd ~/Develop/github.com/kleinbem/kleinbem-secrets

# Edit the fleet-wide default (auto-decrypts, re-encrypts on save)
sops nix/shared.yaml

# Edit a per-host file
sops nix/per-host/core-pi.yaml

# View a specific secret
sops -d nix/shared.yaml | grep vaultwarden_admin_token
```

### 2. Add a New Secret

```bash
# 1. Edit the right file (shared.yaml for fleet-wide, per-host/<host>.yaml
#    for one host, per-container/<name>.yaml for one container)
cd ~/Develop/github.com/kleinbem/kleinbem-secrets
sops nix/shared.yaml
# Add: my_new_secret: "actual-secret-value"
# (sops auto-decrypts/re-encrypts on exit)

# 2. Reference in the host's secrets.nix
```

```nix
# hosts/<device>/secrets.nix
sops.secrets.my_new_secret = { };  # inherits defaultSopsFile (nix/shared.yaml)
# or, for a per-host/per-container file:
sops.secrets.my_new_secret.sopsFile = "${inputs.nix-secrets}/nix/per-host/<device>.yaml";
```

```nix
# used elsewhere in the module
my.secretValue = config.sops.secrets.my_new_secret.path;
```

### 3. Rotate Secrets

```bash
cd ~/Develop/github.com/kleinbem/kleinbem-secrets
sops nix/per-host/<device>.yaml   # or shared.yaml / per-container/<name>.yaml
just save-all "chore: rotate <service> credentials" kleinbem-secrets && just push-all kleinbem-secrets

cd ~/Develop/github.com/kleinbem/nix
just apply   # or: just in nix-config nixos::switch
```

---

## Architecture

### Key Files & Locations

| File | Purpose | Encrypted? |
|------|---------|-----------|
| `kleinbem-secrets/.sops.yaml` | Policy: who can decrypt what, per path | ❌ No (public keys only) |
| `kleinbem-secrets/nix/shared.yaml` | Fleet-wide default secrets | ✅ Yes |
| `kleinbem-secrets/nix/per-host/<host>.yaml` | Secrets scoped to one NixOS host | ✅ Yes |
| `kleinbem-secrets/nix/per-container/<name>.yaml` | Secrets scoped to one standalone container | ✅ Yes |
| `hosts/<device>/secrets.nix` (this repo) | Declares which secrets a host consumes and from where | ❌ No (references only, no values) |
| `/run/secrets/*` | Runtime decrypted (ephemeral, tmpfs) | ❌ No |

### Encryption Keys

```
age keys (see kleinbem-secrets/.sops.yaml for the full recipient list):
  - martin_primary / martin_backup — YubiKey-backed (age-plugin-yubikey), both recipients on every rule
  - one age key per NixOS host — ssh-derived, or TPM-bound (nixos-nvme)
  - OpenWrt device keys, per-persona keys — see .sops.yaml
```

### Access Control (`kleinbem-secrets/.sops.yaml`)

```yaml
keys:
  - &martin_primary age1yubikey1...
  - &martin_backup  age1yubikey1...
  - &core_pi        age1...          # per-host recipient

creation_rules:
  - path_regex: nix/shared\.yaml$
    key_groups:
      - age: [*martin_primary, *martin_backup, *core_pi, ...]   # every host
  - path_regex: nix/per-host/core-pi\.yaml$
    key_groups:
      - age: [*martin_primary, *martin_backup, *core_pi]        # core-pi only
```

Real per-path scoping: a host can only decrypt `shared.yaml` plus its own `per-host/`/`per-container/` files, not the whole store.

---

## Security Patterns

### ✅ DO: Scope Secrets to Features

```nix
# secrets.nix (core host secrets only)
sops.secrets = {
  database_password = { };
  ssh_host_key = { };
};

# ai.nix (AI-specific secrets, gated behind my.ai.enable)
sops.secrets = lib.mkIf config.my.ai.enable {
  openai_key = { };
  claude_api_key = { };
};
```

**Benefit:** Minimal secrets in each file, easier to audit

### ✅ DO: Use Least-Privilege Access

```nix
# Run service as unprivileged user, not root
systemd.services.my_app = {
  serviceConfig = {
    User = "my-app-user";  # Not root
    PrivateTmp = true;      # Isolate /tmp
    ProtectHome = true;     # Can't read home
    ReadWritePaths = [ "/var/lib/my-app" ];
  };
  environment = {
    SECRET_PATH = config.sops.secrets.my_secret.path;
  };
};
```

**Benefit:** If app is compromised, attacker can't read arbitrary files

### ✅ DO: Rotate Credentials Regularly

```bash
cd ~/Develop/github.com/kleinbem/kleinbem-secrets
sops nix/per-host/<device>.yaml   # change the value
just save-all "chore: rotate <service> credentials" kleinbem-secrets && just push-all kleinbem-secrets
cd ~/Develop/github.com/kleinbem/nix && just apply
```

**Benefit:** Limits exposure window if key is leaked

### ✅ DO: Keep Secrets Out of Flake.lock

```nix
# ❌ WRONG: Secrets in options
{ inputs, self, ... }:
options.my.password = mkOption { default = "secret"; };

# ✅ RIGHT: Secrets via sops
config.sops.secrets.my_password.path  # Reference the runtime path, never the value
```

**Benefit:** Flake.lock remains safe to commit/review

### ❌ DON'T: Store Plaintext Secrets Anywhere

```bash
# ❌ WRONG
hosts/*/passwords.nix              # Plaintext, in nix-config
hosts/*/.env                       # Plaintext
flake.nix (embedded secrets)       # Plaintext

# ✅ RIGHT
kleinbem-secrets/nix/**/*.yaml     # sops-encrypted, separate repo
kleinbem-secrets/.sops.yaml        # Encryption policy (public keys only)
```

### ❌ DON'T: Commit Decrypted Secrets

```bash
# ❌ WRONG: Accidentally committing decrypted
sops -d nix/shared.yaml > shared-plain.yaml
git add shared-plain.yaml
git commit

# ✅ RIGHT: Only commit the encrypted .yaml
git add nix/shared.yaml
git commit -m "chore: add secret"
```

**Guard:** Add to `.gitignore` (in `kleinbem-secrets`):
```
*-plain.yaml
*-decrypted
.env
```

---

## Workflow Examples

### Adding a Database Password

```bash
cd ~/Develop/github.com/kleinbem/kleinbem-secrets
sops nix/per-host/core-pi.yaml
# Add: database_password: "super-secure-password-here"
# (nasbook has no nix/per-host/ file yet — this example uses core-pi,
# which does; create nasbook.yaml the same way once it needs one)
just save-all "feat: add core-pi Postgres password" kleinbem-secrets && just push-all kleinbem-secrets
```

```nix
# nix-config/hosts/core-pi/secrets.nix
sops.secrets.database_password.sopsFile = "${inputs.nix-secrets}/nix/per-host/core-pi.yaml";
```

```nix
# nix-config/hosts/core-pi/default.nix
systemd.services.postgres = {
  environment.POSTGRES_PASSWORD_FILE =
    config.sops.secrets.database_password.path;
};
```

```bash
cd ~/Develop/github.com/kleinbem/nix-config
jj describe -m "feat: add Postgres database with encrypted password"
cd ~/Develop/github.com/kleinbem/nix && just push-all nix-config && just apply
```

### Sharing Secrets with a New Host or Persona

```bash
# 1. Generate/extract the new recipient's age public key
#    (host: ssh-to-age on its host key; persona: age-keygen)

# 2. Add an anchor + key_groups entry in kleinbem-secrets/.sops.yaml
cd ~/Develop/github.com/kleinbem/kleinbem-secrets
sops .sops.yaml   # NOT encrypted — public keys only, edit directly, no sops needed for this file itself

# 3. Re-encrypt the affected file(s) to the new recipient
sops updatekeys nix/shared.yaml
```

---

## Troubleshooting

### Issue: "Permission Denied" / Can't Decrypt

**Diagnosis:**
```bash
# Check if a local age key exists (or that the YubiKey is attached —
# fido2-token -L)
ls -la ~/.config/sops/age/

# Check you're a recipient for that path in .sops.yaml
grep -A3 "path_regex" ~/Develop/github.com/kleinbem/kleinbem-secrets/.sops.yaml
```

**Solutions:**
1. Confirm the YubiKey (or local age key) is present and matches a recipient in `.sops.yaml`.
2. Add yourself/the host to the relevant `creation_rules` block if missing.
3. Ask Martin to `sops updatekeys <file>` after the key is added.

### Issue: Secret Not Appearing in `/run/secrets`

**Diagnosis:**
```bash
systemctl status sops-install-secrets
journalctl -u sops-install-secrets -n 20
ls -la /run/secrets/
```

**Solutions:**
1. Restart: `systemctl restart sops-install-secrets`
2. Rebuild: `just apply` (from `nix/`) or `just in nix-config nixos::switch`
3. Check the host declares the secret: `grep -A2 sops.secrets hosts/<device>/secrets.nix`

---

## Integration Examples

### With a Standalone Container

```nix
my.containers.postgres = {
  enable = true;
  environment.DB_PASSWORD_FILE = config.sops.secrets.postgres_password.path;
  # Path is bind-mounted read-only into the container.
};
```

### With Systemd Service

```nix
systemd.services.my-app = {
  after = [ "sops-install-secrets.service" ];
  wants = [ "sops-install-secrets.service" ];

  serviceConfig = {
    User = "my-app-user";
    EnvironmentFiles = [ config.sops.templates."app-env".path ];
  };
};

sops.templates."app-env".content = ''
  API_KEY=${config.sops.placeholder.api_key}
  DB_PASSWORD=${config.sops.placeholder.db_password}
'';
```

---

## Key Rotation Strategy

Same mechanics for every cadence — edit the right `kleinbem-secrets` file, push, redeploy:

```bash
cd ~/Develop/github.com/kleinbem/kleinbem-secrets
sops nix/shared.yaml   # or per-host/<device>.yaml, per-container/<name>.yaml
just save-all "chore: rotate <service> credentials" kleinbem-secrets && just push-all kleinbem-secrets
cd ~/Develop/github.com/kleinbem/nix && just apply
```

- **Monthly** — low-risk dev/API keys.
- **Quarterly** — critical secrets (database/admin passwords).
- **Immediate** — suspected compromise: rotate the specific secret, redeploy, then verify in logs that the new credential is actually in use before considering it closed.

---

## Backup Strategy

**Current State:**
- `kleinbem-secrets` is the encrypted backup — every secret lives there, nowhere else.
- age keys stored locally (`~/.config/sops/age/`) or on YubiKey (preferred — see `fido2-token -L`).

**Recommendations:**

1. **Back up local age keys** (if using one instead of a YubiKey) to an encrypted, offline location.
2. **Verify `kleinbem-secrets` has a remote:** `git -C ~/Develop/github.com/kleinbem/kleinbem-secrets remote -v`.
3. **Never create decrypted files on disk** — pipe straight to `less`:
   ```bash
   sops -d nix/shared.yaml | grep password | less
   # Don't: sops -d nix/shared.yaml > plain.yaml  ❌
   ```

---

## Related Resources

- **Sops Docs:** https://github.com/mozilla/sops
- **Age Docs:** https://age-encryption.org/
- **NixOS Sops Integration:** https://github.com/Mic92/sops-nix
- **Fleet secrets repo:** `kleinbem-secrets/` (sibling repo, see its own README/`.sops.yaml`)

---

## Checklist: Before Deploying Secrets

- [ ] No plaintext copies on disk (`rm *-plain.yaml` in `kleinbem-secrets`)
- [ ] Edited the right file (`shared.yaml` vs `per-host/` vs `per-container/`)
- [ ] `kleinbem-secrets/.sops.yaml` has the right recipients for that path
- [ ] NixOS config references `config.sops.secrets.<name>.path`, never the raw value
- [ ] Test decryption: `sops -d <file>.yaml`
- [ ] Review the diff before committing: `jj diff` (in `kleinbem-secrets`)

---

**Last Updated:** 2026-09-11
**Status:** In active use, proven secure
