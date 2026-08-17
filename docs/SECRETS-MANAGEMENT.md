# Secrets Management Best Practices

**Status:** Secrets encryption via sops + age  
**Updated:** 2026-08-17

Guide to managing secrets securely in the kleinbem fleet using sops, age, and NixOS.

---

## Overview

The kleinbem fleet uses **sops-nix** for encrypted secrets management:

- **Encryption:** age (modern, lightweight)
- **Integration:** sops (simple, human-editable encrypted files)
- **Tool:** sops CLI for encrypting/decrypting
- **Backup:** kleinbem-secrets repository (sops + age encrypted)

```
plaintext secret → age encryption → sops file → git commit → deploy
                                     ↑
                              nix eval + activation
```

---

## Quick Start

### 1. Access Existing Secrets (Development)

```bash
# List encrypted secrets
sops nix-config/secrets.yaml

# Edit secrets (auto-decrypts, re-encrypts on save)
sops hosts/core-pi/secrets.yaml

# View specific secret
sops -d hosts/core-pi/secrets.yaml | grep password
```

### 2. Add a New Secret

```bash
# 1. Edit the secrets file
sops hosts/<device>/secrets.yaml

# 2. Add new key-value pair
# my_new_secret: "actual-secret-value"
# (sops auto-decrypts/re-encrypts on exit)

# 3. Use in NixOS config
sops.secrets.my_new_secret.path
# Or:
config.sops.secrets.my_new_secret.path

# 4. Reference in module
my = {
  secretValue = config.sops.secrets.my_new_secret.path;
};
```

### 3. Rotate Secrets

```bash
# Edit to change value
sops hosts/<device>/secrets.yaml

# Commit and deploy
jj describe -m "chore: rotate <service> credentials"
jj git push && nixos-rebuild switch
```

---

## Architecture

### Key Files & Locations

| File | Purpose | Encrypted? |
|------|---------|-----------|
| `.sops.yaml` | Root config (policy: who can decrypt what) | ❌ No |
| `hosts/*/secrets.yaml` | Per-device encrypted secrets | ✅ Yes |
| `nix-secrets/` | Shared encrypted secrets (age-encrypted) | ✅ Yes |
| `kleinbem-secrets/` | Fleet-wide secrets archive | ✅ Yes |
| `/run/secrets/*` | Runtime decrypted (ephemeral) | ❌ No |

### Encryption Keys

```
age keys:
  - ~/.config/sops/age/keys.txt (personal, local)
  - YubiKey (SSH FIDO2, for remote signing)

GPG keys:
  - ~/.gnupg/ (optional, not used in current setup)
```

### Access Control (.sops.yaml)

```yaml
keys:
  - age_recipient: age1...  # Your personal age key
    # Allows decryption with:
    # sops -d file.yaml

encrypted_regex: ^(password|secret|token|key|credentials)

# Per-file overrides (in file metadata)
# kms: [ arn:aws:kms:... ]  # If using AWS KMS
```

---

## Security Patterns

### ✅ DO: Scope Secrets to Features

```nix
# secrets.nix (core host secrets only)
sops.secrets = {
  database_password.path;
  ssh_host_key.path;
};

# ai.nix (AI-specific secrets, gated behind my.ai.enable)
sops.secrets = lib.mkIf config.my.ai.enable {
  openai_key.path;
  claude_api_key.path;
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
# Quarterly
sops hosts/<device>/secrets.yaml
# Change password/token values

# Commit
jj describe -m "chore: rotate <service> credentials (Q3 2026)"

# Deploy
nixos-rebuild switch
```

**Benefit:** Limits exposure window if key is leaked

### ✅ DO: Keep Secrets Out of Flake.lock

```nix
# ❌ WRONG: Secrets in options
{ inputs, self, ... }:
options.my.password = mkOption { default = "secret"; };

# ✅ RIGHT: Secrets via sops
sops.secrets.my_password.path;
config.sops.secrets.my_password.path  # Reference
```

**Benefit:** Flake.lock remains safe to commit/review

### ❌ DON'T: Store Plaintext Secrets Anywhere

```bash
# ❌ WRONG
hosts/*/passwords.nix          # Plaintext
hosts/*/.env                    # Plaintext
flake.nix (embedded secrets)    # Plaintext

# ✅ RIGHT
hosts/*/secrets.yaml            # sops-encrypted
.sops.yaml                      # Encryption policy
```

### ❌ DON'T: Commit Decrypted Secrets

```bash
# ❌ WRONG: Accidentally committing decrypted
sops -d secrets.yaml > secrets-plain.yaml
git add secrets-plain.yaml
git commit

# ✅ RIGHT: Only commit .yaml (encrypted)
git add secrets.yaml
git commit -m "chore: add secret"
```

**Guard:** Add to .gitignore:
```
secrets-*-plain.yaml
*-decrypted
.env
```

---

## Workflow Examples

### Adding a Database Password

```bash
# 1. Edit secrets file
sops hosts/nasbook/secrets.yaml

# 2. Add to file:
database_password: "super-secure-password-here"

# 3. Use in NixOS config:
# hosts/nasbook/default.nix
systemd.services.postgres = {
  environment.POSTGRES_PASSWORD_FILE = 
    config.sops.secrets.database_password.path;
};

# 4. Commit
jj describe -m "feat: add Postgres database with encrypted password"
jj git push

# 5. Deploy
nixos-rebuild switch
```

### Rotating API Key

```bash
# 1. Old key
sops -d hosts/core-pi/secrets.yaml | grep api_key
# api_key: old-key-abc123

# 2. Edit
sops hosts/core-pi/secrets.yaml
# Change: api_key: new-key-xyz789

# 3. Deploy immediately
jj describe -m "chore: rotate core-pi API key"
jj git push && nixos-rebuild switch

# 4. Verify new key is working
systemctl status <service>
tail -f /var/log/<service>
```

### Sharing Secrets with Team Member

```bash
# 1. Get their age public key
age-keygen -o  # Generate if they don't have one
cat ~/.config/sops/age/keys.txt | grep "# public key:"

# 2. Update .sops.yaml with their key
sops .sops.yaml
# Add their age_recipient line

# 3. Re-encrypt all files
sops updatekeys hosts/*/secrets.yaml

# 4. They can now decrypt
git pull
sops -d hosts/*/secrets.yaml
```

---

## Troubleshooting

### Issue: "Permission Denied" / Can't Decrypt

**Diagnosis:**
```bash
# Check if age key exists
cat ~/.config/sops/age/keys.txt
ls -la ~/.config/sops/age/

# Check if you're in .sops.yaml
grep "age_recipient" .sops.yaml | grep "$(grep 'public key' ~/.config/sops/age/keys.txt)"

# Try decrypting
sops -d hosts/core-pi/secrets.yaml
```

**Solutions:**
1. Generate age key if missing: `age-keygen -o`
2. Add to `.sops.yaml` if not there
3. Ask another maintainer to re-encrypt: `sops updatekeys hosts/*/secrets.yaml`

### Issue: "invalid recipient"

**Cause:** Age key in .sops.yaml is invalid format

**Fix:**
```bash
# Get correct public key format
age-keygen -o ~/.config/sops/age/keys.txt
cat ~/.config/sops/age/keys.txt | grep "# public key:"
# Format: age1...

# Update .sops.yaml with correct format
sops .sops.yaml
# Fix the age_recipient line
```

### Issue: Secret Not Appearing in /run/secrets

**Diagnosis:**
```bash
# Check if sops-install-secrets ran
systemctl status sops-install-secrets
journalctl -u sops-install-secrets -n 20

# Check if file exists
ls -la /run/secrets/

# Check systemd-tmpfiles
systemd-tmpfiles --create
```

**Solutions:**
1. Restart sops: `systemctl restart sops-install-secrets`
2. Rebuild system: `nixos-rebuild switch`
3. Check config has secret defined: `grep sops.secrets hosts/<device>/secrets.nix`

---

## Integration Examples

### With Container

```nix
my.containers.postgres = {
  enable = true;
  ip = "...";
  environment.DB_PASSWORD_FILE = 
    config.sops.secrets.postgres_password.path;
  # Path is mounted read-only into container
};
```

### With Systemd Service

```nix
systemd.services.my-app = {
  after = [ "sops-install-secrets.service" ];
  wants = [ "sops-install-secrets.service" ];
  
  serviceConfig = {
    User = "my-app-user";
    EnvironmentFiles = [ 
      config.sops.templates."app-env".path 
    ];
  };
};

sops.templates."app-env".content = ''
  API_KEY=${config.sops.secrets.api_key.path}
  DB_PASSWORD=${config.sops.secrets.db_password.path}
'';
```

### With Environment Variables

```nix
environment.variables.API_KEY_FILE = 
  config.sops.secrets.api_key.path;

# Then in shell
echo $API_KEY_FILE  # /run/secrets.d/api_key
cat $API_KEY_FILE   # Actual value
```

---

## Key Rotation Strategy

### Monthly Rotation (Low-Risk Secrets)

```bash
# Mark in calendar: "Rotate dev API keys"
sops hosts/<device>/secrets.yaml
# Update: dev_api_key
jj describe -m "chore: monthly rotation of dev credentials"
jj git push
```

### Quarterly Rotation (Critical Secrets)

```bash
# Password rotation
sops hosts/*/secrets.yaml
# Update: database_password, admin_password, etc.
jj describe -m "chore: Q3 credential rotation"
jj git push
```

### Immediate Rotation (Suspected Compromise)

```bash
# If key was exposed/leaked
sops hosts/*/secrets.yaml  # Change ALL affected secrets
jj describe -m "fix: URGENT — rotate leaked credentials"
jj git push && nixos-rebuild switch
# Verify in logs that new credentials work
```

---

## Backup Strategy

**Current State:**
- kleinbem-secrets repo contains encrypted secrets (backed up)
- sops files encrypted with age keys (minimal plaintext)
- age keys stored locally (protect with OS-level encryption)

**Recommendations:**

1. **Backup age keys (secure location):**
   ```bash
   # Annual backup
   cp ~/.config/sops/age/keys.txt /encrypted-backup/
   # Store on encrypted USB drive
   ```

2. **Backup sops files:**
   ```bash
   # Already in kleinbem-secrets repo
   # Verify remote: git remote -v
   ```

3. **Audit decrypted values:**
   ```bash
   # Never store decrypted versions
   # If grep'ing, pipe to less (don't create files)
   sops -d secrets.yaml | grep password | less
   # Don't: sops -d secrets.yaml > secrets.txt  ❌
   ```

---

## Related Resources

- **Sops Docs:** https://github.com/mozilla/sops
- **Age Docs:** https://age-encryption.org/
- **NixOS Sops Integration:** https://github.com/Mic92/sops-nix
- **Fleet Repo:** `kleinbem-secrets/` (encrypted backup)

---

## Checklist: Before Deploying Secrets

- [ ] No plaintext copies on disk (`rm secrets-*.txt`)
- [ ] .sops.yaml permissions are correct (`chmod 600`)
- [ ] .gitignore includes plaintext patterns
- [ ] sops file is encrypted (try `file secrets.yaml`)
- [ ] All age recipients in .sops.yaml are valid
- [ ] NixOS config references `config.sops.secrets.X.path`
- [ ] Test decryption: `sops -d secrets.yaml`
- [ ] Review diff before commit: `git diff --cached`
- [ ] Clean up any temp files: `ls /tmp/*secret*`

---

**Last Updated:** 2026-08-17  
**Status:** In active use, proven secure  
**Next:** Document key rotation procedures, backups
