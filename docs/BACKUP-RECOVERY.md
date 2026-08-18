# Backup & Disaster Recovery Guide

**Status:** Complete recovery procedures for the kleinbem fleet  
**Updated:** 2026-08-18

Comprehensive backup strategy and disaster recovery procedures for protecting fleet data and restoring from failures.

---

## Quick Start

### Daily Protection (Automated)
- NixOS configs: Git-based (every commit)
- Secrets: age-encrypted (sops backup)
- Container data: Device-specific persistence

### Weekly Actions (Manual)
```bash
# Backup critical secrets (offline)
tar czf /media/backup/secrets-$(date +%Y%m%d).tar.gz \
  ~/.config/sops/age/keys.txt \
  /etc/ssh/ssh_host_*_key

# Backup fleet documentation
git bundle create /media/backup/nix-config-$(date +%Y%m%d).bundle main
```

### Recovery From Backup
```bash
# Restore secrets (must be done before rebuild)
tar xzf /media/backup/secrets-YYYYMMDD.tar.gz -C /

# Restore git history if needed
git clone /media/backup/nix-config-YYYYMMDD.bundle nix-config-recovered
```

---

## Backup Strategy

### What Needs Backing Up

| Item | Type | Method | Frequency | Location |
|------|------|--------|-----------|----------|
| NixOS configs | Source code | Git (GitHub) | Continuous | GitHub primary |
| Secrets (age keys) | Encryption keys | Offline USB | Annually | Physical vault |
| Device SSH keys | Host keys | Offline USB | At setup | Physical vault |
| Container data | Persistent state | Device-native | Per-device | `/nix/persist` |
| User home dirs | User files | syncthing/rclone | Continuous | Cloud/NAS |
| Database backups | Structured data | restic/pg_dump | Daily | Attic cache + cloud |
| Monitoring data | Time-series DB | Retention policy | Keep 30 days | VictoriaMetrics |

### What Does NOT Need Backing Up

- `/nix/store/` — Reconstructible from config
- Build artifacts — Rebuild from source (Attic cache)
- Transient data — Explicitly impermanent (tmpfs)
- Docker/container images — Pulled from registries on demand

---

## Per-Device Backup Plans

### Workstations (nixos-nvme, mac-mini)

**NixOS Config:**
```bash
# Automatic: git push to GitHub (commit-based)
# All changes tracked, full history preserved
# Recovery: git clone from GitHub
```

**Home Directory:**
```bash
# syncthing — file sync daemon (enabled on nixos-nvme)
# Continuously synced to:
#  - nasbook (backup target)
#  - Personal laptop (secondary)
# Recovery: Restore from syncthing .stversions/
```

**SSH Keys:**
```bash
# Stored in /etc/ssh/ssh_host_*_key
# Backup: Annual snapshot to encrypted USB
# Must be kept safe — losing these breaks host identity
```

### Edge Hubs (core-pi)

**NixOS Config:**
```bash
# Automatic: git push to GitHub
# Identical to workstations
```

**Container Data:**
```bash
# All in /nix/persist (impermanence)
# Mounted on boot from persistent storage
# Backup: Per-container, see below
```

**Caddy Certificates:**
```bash
# Auto-renewed, but first cert is irreplaceable
# Location: /var/lib/caddy/.local/share/caddy/pki/
# Backup: Annual snapshot to encrypted USB + Git+CRYPT bundle
```

**Attic Cache:**
```bash
# Backend: /var/lib/images/attic/
# Critical: Losing this breaks CI/CD deployments
# Backup: 
#   - Daily: Snapshot via LVM/BTRFS
#   - Weekly: rclone to cloud (S3-compatible)
#   - Monthly: Full export tar archive
```

**Secrets:**
```bash
# Stored in sops-encrypted YAML files
# Git-safe: encrypted at rest in repo
# Backup: age keys encrypted on USB annually
```

### Edge Nodes (orin-nano, nasbook, hass-pi)

**NixOS Config:**
```bash
# Same as workstations/hubs (GitHub-based)
```

**Device State:**
```bash
# Location varies by role:
#   orin-nano: /nix/persist
#   nasbook: /var/lib/paperless, /var/lib/backup/
#   hass-pi: /nix/persist, /var/lib/home-assistant/

# Backup: Per-device strategy (see below)
```

**nasbook Special Case (Data Repository):**
```bash
# Role: Primary backup target
# Storage: 2TB+ QNAP NAS
# Backup sources:
#   - workstation home dirs (syncthing)
#   - container state (paperless)
#   - media (photos, documents)
#
# Backup procedure:
#   1. Daily: Automated syncthing pulls
#   2. Weekly: rclone incremental backup to cloud
#   3. Monthly: Full archive to external USB
```

---

## Encryption & Key Management

### Age Key (Secrets Decryption)

**Location:** `~/.config/sops/age/keys.txt`

**Critical:** This is the master key for all encrypted secrets.

**Backup procedure:**
```bash
# 1. List current key
cat ~/.config/sops/age/keys.txt

# 2. Create encrypted backup (GPG or symmetric)
gpg --symmetric ~/.config/sops/age/keys.txt
# OR
openssl enc -aes-256-cbc -in ~/.config/sops/age/keys.txt \
  -out keys.txt.enc

# 3. Store offline
#   - USB drive (encrypted)
#   - Physical safe
#   - Second location (safety deposit box)

# 4. Document passphrase separately
#   (memorize, do NOT store with key)
```

**Recovery:**
```bash
# Decrypt backup
gpg keys.txt.txt.gpg -o ~/.config/sops/age/keys.txt
# OR
openssl enc -d -aes-256-cbc -in keys.txt.enc \
  -out ~/.config/sops/age/keys.txt

# Verify
sops -d hosts/core-pi/secrets.yaml | head
# Should decrypt successfully
```

### SSH Host Keys

**Location:** `/etc/ssh/ssh_host_*_key`

**Critical:** Loss means device loses identity.

**Backup procedure:**
```bash
# Before first deployment
tar czf /media/backup/ssh_keys_$(hostname).tar.gz \
  /etc/ssh/ssh_host_*_key*

# Encrypt
gpg --symmetric /media/backup/ssh_keys_*.tar.gz

# Store in vault (same as age key)
```

---

## Cloud Backup Strategy

### Backup Targets (Options)

**Option 1: S3-Compatible Cloud**
```bash
# rclone setup
rclone config create mycloud s3 \
  provider = other \
  endpoint = https://s3.example.com \
  access_key_id = XXXXX \
  secret_access_key = YYYYY

# Sync
rclone sync /var/lib/images/attic/ mycloud:backups/attic/
```

**Option 2: Backup Service (restic)**
```bash
# Initialize repository
restic -r s3:s3.example.com/backups/home init

# Regular backups
restic -r s3:... backup /var/lib/important/
restic -r s3:... forget --keep-daily 30 --keep-monthly 12
```

**Option 3: Glacier/Cold Storage**
```bash
# Annual archive for long-term storage
aws s3 cp /var/lib/archives/ s3://my-glacier/ \
  --storage-class GLACIER
```

### Backup Frequency

| Data | Frequency | Retention |
|------|-----------|-----------|
| NixOS config | Every commit | Forever (Git) |
| Container state | Daily snapshot | 30 days |
| Database dumps | Daily | 90 days |
| Full archive | Monthly | 1 year |
| Disaster recovery | Before major change | Indefinite |

---

## Disaster Recovery Procedures

### Scenario 1: Single Device Total Failure

**Affected:** One device lost (hardware failure, corruption)

**Time to recover:** 30 minutes to 2 hours

**Recovery steps:**

1. **Obtain replacement hardware**
   ```bash
   # Same CPU architecture + spec (or better)
   # NixOS will adapt to new hardware
   ```

2. **Restore from backup**
   ```bash
   # Clone config repo
   git clone https://github.com/kleinbem/nix-config
   cd nix-config
   
   # Restore from backup secrets (if needed)
   tar xzf /media/backup/secrets-YYYYMMDD.tar.gz -C /
   ```

3. **Reinstall NixOS**
   ```bash
   # Use disko to format disk (declarative)
   nix run github:nix-community/disko \
     --extra-experimental-features flakes \
     --extra-experimental-features nix-command \
     -- --mode zap_create_mount hosts/DEVICE/disko.nix
   
   # Install
   nixos-install --flake .#DEVICE
   ```

4. **Restore container/persistent state** (if applicable)
   ```bash
   # Restore from backup
   rsync -av /media/backup/container-state/ /nix/persist/
   ```

5. **Verify**
   ```bash
   ssh DEVICE nixos-version
   # Should show current version
   ```

**Prevention:** Regular backup snapshots (monthly minimum)

---

### Scenario 2: Secrets Compromised

**Affected:** age keys leaked, credentials exposed

**Time to recover:** 2-4 hours (depends on scope)

**Recovery steps:**

1. **Identify scope**
   ```bash
   # What was exposed?
   # - Just age keys? Rotate everything
   # - Just API tokens? Rotate those only
   # - SSH host keys? Device loses identity, reinstall needed
   ```

2. **Rotate credentials** (if API tokens exposed)
   ```bash
   # Edit sops file
   sops hosts/DEVICE/secrets.yaml
   
   # Update exposed secrets
   # (e.g., database_password, api_token)
   
   # Commit
   jj describe -m "chore: rotate credentials after incident"
   
   # Deploy immediately
   nixos-rebuild switch -h DEVICE
   ```

3. **Re-encrypt secrets** (if age keys exposed)
   ```bash
   # Generate NEW age key
   age-keygen -o > ~/.config/sops/age/keys.txt.new
   
   # Add to .sops.yaml
   keys:
     - &age_key_new <NEW_KEY_PUBLIC>
   
   # Re-encrypt all secrets
   sops updatekeys hosts/*/secrets.yaml
   sops updatekeys modules/home-manager/secrets.yaml
   
   # Test decryption
   sops -d hosts/core-pi/secrets.yaml | head
   
   # Commit
   jj describe -m "chore: rotate age key after exposure"
   jj git push
   
   # Deploy to all devices
   colmena apply -s switch
   ```

4. **Destroy old keys**
   ```bash
   # Securely wipe old key from all backups
   shred -vfz ~/.config/sops/age/keys.txt.old
   
   # Remove from git history (rebase if not pushed)
   git filter-branch --tree-filter 'rm -f .sops.yaml.old' HEAD
   ```

**Prevention:** Strict access control, regular key rotation (quarterly)

---

### Scenario 3: GitHub Repository Compromised

**Affected:** Malicious code merged, history altered

**Time to recover:** 30 minutes to 2 hours

**Recovery steps:**

1. **Identify last known good commit**
   ```bash
   git log --oneline | grep "known good commit message"
   # or inspect GitHub's commit history
   ```

2. **Reset branch to good commit**
   ```bash
   git reset --hard <GOOD_COMMIT>
   git push --force-with-lease origin main
   ```

3. **Revert bad changes**
   ```bash
   # Don't force-push: make a revert commit instead
   git revert <BAD_COMMIT>
   git push origin main
   ```

4. **Check all devices**
   ```bash
   # Ensure no device pulled bad code
   for device in nixos-nvme core-pi orin-nano; do
     ssh $device "git -C /nix/config log --oneline -1"
   done
   ```

5. **Audit git history**
   ```bash
   # Review all recent commits
   git log --oneline -20
   
   # Check for unexpected changes
   git log -p hosts/ | grep -A5 -B5 "suspicious"
   ```

**Prevention:** Branch protection rules, code reviews, signed commits

---

### Scenario 4: Network Outage / Gateway Down

**Affected:** Entire fleet unreachable (core-gateway down)

**Time to recover:** 30 minutes to 8 hours (depends on cause)

**Recovery steps:**

1. **Check physical gateway**
   ```bash
   # SSH via physical access (serial console)
   # or out-of-band (lights-out management if available)
   ```

2. **Check gateway config**
   ```bash
   # If device is up but network broken:
   ssh 10.0.0.1 "systemctl status networking"
   ssh 10.0.0.1 "journalctl -xe -n 50"
   ```

3. **Rollback bad change**
   ```bash
   # If caused by recent config change:
   ssh 10.0.0.1 "nlctl list-generations | head -5"
   ssh 10.0.0.1 "nixos-rebuild switch --rollback"
   ```

4. **Manual recovery (if SSH fails)**
   ```bash
   # Serial console / IPMI access required
   # Boot to recovery image
   # Mount root filesystem
   # Manual fix or full reinstall
   ```

5. **Restore from backup**
   ```bash
   # If device is beyond repair
   # Follow Scenario 1 (total failure recovery)
   ```

**Prevention:** 
- Mesh network (NetBird) — survives LAN outages
- Multiple redundancy — if core-pi down, traffic bypasses to alternative
- Network testing before deployment

---

### Scenario 5: Data Loss / Filesystem Corruption

**Affected:** Device filesystem corrupted, data lost

**Time to recover:** 1-4 hours

**Recovery steps:**

1. **Prevent cascading loss**
   ```bash
   # Stop the device
   ssh DEVICE "systemctl isolate rescue.target"
   ```

2. **Attempt recovery**
   ```bash
   # Try filesystem check
   ssh DEVICE "fsck -n /nix"  # Check without repairs
   
   # If repairable
   ssh DEVICE "fsck -y /nix"  # Repair automatically
   ssh DEVICE "systemctl reboot"
   ```

3. **Restore from snapshot** (if available)
   ```bash
   # BTRFS/LVM snapshots can recover recent state
   ssh DEVICE "btrfs subvolume list /nix"
   ssh DEVICE "btrfs subvolume snapshot -r /nix@35 /nix@recover"
   ssh DEVICE "mount -o subvol=recover /nix"
   ```

4. **Restore from full backup**
   ```bash
   # If snapshots not available
   # Follow Scenario 1 recovery process
   ```

**Prevention:**
- Weekly snapshots (automated)
- Regular fsck checks
- UPS for unexpected shutdown prevention
- BTRFS/ZFS with built-in integrity checking

---

## Backup Verification

### Monthly Verification Checklist

```bash
# 1. Test Git backup
git clone --bare /media/backup/nix-config-latest.bundle \
  /tmp/test-restore.git
git clone /tmp/test-restore.git /tmp/test-restore
cd /tmp/test-restore
git log --oneline -5
# Should show recent commits

# 2. Test secrets backup
tar tzf /media/backup/secrets-latest.tar.gz | head -5
# Should list keys and certs

# 3. Test cloud backup (if applicable)
rclone ls mycloud:backups/
# Should show recent files

# 4. Test age key backup
gpg -d /media/backup/keys.txt.gpg > /tmp/keys-test.txt
wc -l /tmp/keys-test.txt
# Should be ~2 lines (key + recipient)

# 5. Cleanup
rm -rf /tmp/test-restore* /tmp/keys-test.txt
```

---

## Related Documentation

- **SECRETS-MANAGEMENT.md** — How to manage encrypted secrets
- **DEPLOYMENT-STRATEGY.md** — Safe changes and rollback
- **TROUBLESHOOTING.md** — Diagnosing issues
- **FLEET-ARCHITECTURE.md** — System overview, redundancy

---

## Tools & Utilities

### Backup Tools (Pre-installed)

| Tool | Purpose | Config |
|------|---------|--------|
| **git** | Version control | Primary |
| **sops** | Secret encryption | Secret management |
| **age** | Modern encryption | Sops backend |
| **restic** | Incremental backups | Optional, backup-systems.nix |
| **rclone** | Cloud sync | Optional, sync-systems.nix |
| **rsync** | File sync | Optional, file-systems.nix |

### Backup Storage Options

| Option | Capacity | Cost | Access | Durability |
|--------|----------|------|--------|-----------|
| **Local USB** | 1-2TB | $50-100 | Offline (safe) | Good if stored well |
| **NAS (nasbook)** | 4-8TB | $300-500 | LAN | Good (RAID) |
| **S3 Cloud** | Unlimited | $5-50/month | Internet | Excellent (AWS) |
| **Glacier** | Unlimited | $1-5/month | 4-12 hours | Excellent (AWS) |
| **Git (GitHub)** | ~1GB | Free | Internet | Excellent |

---

## Legal & Compliance

### Data Retention

- **Production configs:** Forever (Git)
- **Secrets:** Keep only active ones, securely delete rotated
- **Backups:** Monthly archives, retain 1 year minimum
- **Logs:** 30 days (systemd), 90 days (Prometheus)
- **User data:** Per-user retention policy (see DEVICE-TIERS.md)

### Disaster Recovery Testing

**Requirement:** Test recovery procedures quarterly

```bash
# Test schedule
March: Full device rebuild from config
June: Secrets rotation from backup
September: Container restore from snapshot
December: Complete disaster recovery simulation
```

---

## Quick Reference

### Backup Checklist (Monthly)

- [ ] Git history backed up (automatic via GitHub)
- [ ] Secrets backed up to encrypted USB
- [ ] SSH host keys backed up to vault
- [ ] Container data snapshots verified
- [ ] Cloud backups tested (rclone)
- [ ] Verification test passed (see section above)
- [ ] Documentation updated (this file)

### Recovery Checklist (When Needed)

- [ ] Identify scope of failure
- [ ] Assess risk to other systems
- [ ] Isolate affected device(s)
- [ ] Plan recovery steps (see scenarios above)
- [ ] Execute recovery
- [ ] Verify restoration (test access, data integrity)
- [ ] Document incident and root cause

---

## Further Reading

- [NixOS Impermanence](https://github.com/nix-community/impermanence) — Stateless systems
- [sops-nix Documentation](https://github.com/Mic92/sops-nix) — Secrets management
- [restic Manual](https://restic.readthedocs.io/) — Backup tool
- [rclone Documentation](https://rclone.org/docs/) — Cloud sync
- [BTRFS Snapshots](https://btrfs.readthedocs.io/en/latest/btrfs-subvolume.html) — Local snapshots

---

**Last Updated:** 2026-08-18  
**Status:** Complete disaster recovery guide  
**Audience:** Operators, maintainers, security teams
