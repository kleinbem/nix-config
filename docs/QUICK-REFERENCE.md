# Quick Reference Guide

**Cheat sheet for common kleinbem fleet operations**

---

## Device IPs (LAN)

```
nixos-nvme:   10.0.0.5     mac-mini:     10.0.0.16
core-pi:      10.0.0.22    orin-nano:    10.0.0.15
nasbook:      10.0.0.30    hass-pi:      10.0.0.21
core-gateway: 10.0.0.1     ap-upstairs:  10.0.0.2
```

---

## SSH Quick Access

```bash
ssh martin@10.0.0.5      # nixos-nvme
ssh martin@10.0.0.22     # core-pi
ssh martin@10.0.0.16     # mac-mini
ssh martin@10.0.0.15     # orin-nano
ssh martin@10.0.0.30     # nasbook
```

---

## Local Development

### Edit & Test

```bash
# Syntax check
nix eval '.#nixosConfigurations.nixos-nvme.config.system.nixos.version'

# Build locally (no activation)
nixos-rebuild build

# Dry-run (see what would change)
nixos-rebuild dry-activate

# Activate (apply changes)
nixos-rebuild switch
```

### Review Changes

```bash
# See diffs before committing
jj diff HEAD~1

# See recent commits
jj log -n 10

# See working copy status
jj status
```

---

## Committing Changes

```bash
# Create/edit commit (opens editor)
jj describe

# Or with message directly
jj describe -m "feat: add new module"

# Sign and push to GitHub (requires YubiKey)
jj git push
```

---

## Fleet-Wide Commands

```bash
# From anywhere in workspace (or conductors nix/, openwrt/)

just status-all              # See all repos + uncommitted changes
just status-all nix          # Filter by substring (just nix* repos)
just diff-all                # Show diffs across fleet
just diff-all nix --stat     # With stats
just remote-status           # GitHub CI/PR/issue status
just remote-prs              # List open PRs
just remote-ci 5             # Last 5 CI runs per repo
just push-all                # Push all dirty repos
just pull-all                # Fetch + rebase all
just bootstrap               # Clone missing repos

# From a conductor (nix/, openwrt/, kleinbem/)
just jj::save-all "msg"      # jj describe in all repos
just jj::sign-unsigned       # Sign all unsigned commits
just jj::push-all            # Push all to GitHub
```

---

## Device Deployment

### Dry-run (Check What Changes)

```bash
nixos-rebuild dry-activate -h 10.0.0.15  # orin-nano

# Check if it would work
systemctl status                          # On device, after activation
```

### Deploy to Device

```bash
# Basic deploy
nixos-rebuild switch -h 10.0.0.15        # orin-nano

# With specific config
nix run '.#config-machines.orin-nano'    # If available

# Fallback to cache (don't rebuild locally)
nixos-rebuild switch -h 10.0.0.15 --fallback
```

### Rollback After Bad Deploy

```bash
# From the device (via SSH)
nixos-rebuild switch --rollback

# Or from your machine
ssh 10.0.0.15 "nixos-rebuild switch --rollback"
```

---

## Secrets Management

### View Encrypted Secrets

```bash
# Show (decrypted) content
sops -d hosts/core-pi/secrets.yaml

# Show specific key
sops -d hosts/core-pi/secrets.yaml | grep api_key

# Without decrypting (file metadata)
file hosts/core-pi/secrets.yaml
```

### Edit Secrets

```bash
# Edit interactively (auto-decrypt/re-encrypt on save)
sops hosts/core-pi/secrets.yaml

# Add new key
# 1. Open file: sops hosts/core-pi/secrets.yaml
# 2. Add: new_secret: "value"
# 3. Save (auto-encrypted)
# 4. Commit: jj describe -m "chore: add secret"
```

### Rotate Credentials

```bash
# 1. Edit
sops hosts/core-pi/secrets.yaml

# 2. Change value (e.g., database_password)

# 3. Commit
jj describe -m "chore: rotate core-pi credentials"

# 4. Deploy immediately
nixos-rebuild switch -h 10.0.0.22
```

---

## Troubleshooting

### Device Not Reachable

```bash
# 1. Check if it's on LAN
ping 10.0.0.22

# 2. Check SSH
ssh -vvv martin@10.0.0.22    # Verbose

# 3. Check NixOS
ssh 10.0.0.22 "nixos-version"

# 4. See recent logs (on device)
ssh 10.0.0.22 "journalctl -xe -n 30"
```

### Build Failed

```bash
# See full error
nix build .#nixosConfigurations.core-pi.config.system.build.toplevel 2>&1 | head -50

# Check specific config
nix eval .#nixosConfigurations.core-pi.config.system.nixos.version

# Revert bad commit
jj revert <commit-hash>
jj git push
```

### Container Not Starting

```bash
# On the device
ssh core-pi "systemctl status container@caddy"
ssh core-pi "journalctl -u container@caddy -n 30"
ssh core-pi "machinectl list"
```

### Secrets Not Decrypting

```bash
# Check age key
ls ~/.config/sops/age/keys.txt

# Test decryption
sops -d hosts/core-pi/secrets.yaml | head

# Re-encrypt if needed
sops updatekeys hosts/*/secrets.yaml
```

---

## Cache & Dependencies

### Check Cache Status

```bash
# Is Attic running?
curl https://cache.kleinbem.dev/nix-cache-info

# What's in the cache?
nix flake info

# Force rebuild (don't use cache)
nixos-rebuild build --no-substitute
```

### Refresh Flake Inputs

```bash
# Update all inputs
nix flake update

# Update one input
nix flake update nixpkgs

# Check what would change
git diff flake.lock
```

---

## Monitoring

### Check Monitoring Status

```bash
# SSH to mac-mini
ssh mac-mini

# Check if monitoring is running
systemctl status monitoring

# Check Prometheus
curl http://10.85.48.106:9090/api/v1/targets
```

### Check Cache (Attic)

```bash
# SSH to core-pi
ssh core-pi

# Check container status
systemctl status container@attic

# Check logs
journalctl -u container@attic -n 50
```

---

## Container Operations

### Check Containers on Host

```bash
# List all containers
ssh core-pi "machinectl list"

# Check one container
ssh core-pi "systemctl status container@caddy"

# See container logs
ssh core-pi "journalctl -u container@caddy -n 50"

# Restart container
ssh core-pi "systemctl restart container@caddy"
```

### Access Container Shell

```bash
# SSH into container
ssh core-pi
machinectl shell caddy /bin/bash

# Or directly
systemd-nspawn -i /var/lib/machines/caddy /bin/bash
```

---

## Health Checks

### Quick Fleet Audit

```bash
# Run health check script
./tools/fleet-health-check.sh

# Check one device
./tools/fleet-health-check.sh core-pi

# Verbose output
./tools/fleet-health-check.sh --verbose
```

### Manual Checks

```bash
# System load
ssh <device> "top -b -n 1 | head -5"

# Disk usage
ssh <device> "df -h"

# Memory
ssh <device> "free -h"

# Failed services
ssh <device> "systemctl list-failed"
```

---

## Documentation

### Find What You Need

- **Setting up a new device?** → `docs/DEVICE-TIERS.md`
- **Understanding modules?** → `docs/MODULE-ORGANIZATION.md`
- **Something broken?** → `docs/TROUBLESHOOTING.md`
- **Need to rotate secrets?** → `docs/SECRETS-MANAGEMENT.md`
- **Deploying changes?** → `docs/DEPLOYMENT-STRATEGY.md`
- **Understand the architecture?** → `docs/FLEET-ARCHITECTURE.md`

---

## Common Workflows

### Add a New Device

```bash
# 1. Follow DEVICE-TIERS.md template
# 2. Create hosts/<device-name>/
# 3. Run health check
./tools/fleet-health-check.sh <device-name>
# 4. Deploy
nixos-rebuild switch -h 10.0.0.XX
```

### Deploy to All Devices (Phased)

```bash
# Phase 1: Edge testing
nixos-rebuild switch -h 10.0.0.15  # orin-nano

# Phase 2: Non-critical
nixos-rebuild switch -h 10.0.0.30  # nasbook

# Phase 3: Production
nixos-rebuild switch -h 10.0.0.22  # core-pi
nixos-rebuild switch -h 10.0.0.16  # mac-mini

# Phase 4: Gateway
# (OpenWrt - different workflow)
```

### Rotate Credentials

```bash
sops hosts/<device>/secrets.yaml
# Edit values
jj describe -m "chore: rotate credentials"
jj git push
nixos-rebuild switch -h 10.0.0.XX
```

### Emergency Rollback

```bash
# Revert bad commit
jj revert <commit-hash>
jj git push

# Roll back device to previous generation
ssh <device> "nixos-rebuild switch --rollback"
```

---

## Useful aliases (add to ~/.bashrc)

```bash
# Fleet commands
alias jfleet='just status-all'
alias jpush='just push-all'

# Device SSH shortcuts
alias ssh-nvme='ssh martin@10.0.0.5'
alias ssh-pi='ssh martin@10.0.0.22'
alias ssh-mini='ssh martin@10.0.0.16'
alias ssh-jetson='ssh martin@10.0.0.15'

# NixOS rebuild
alias rebuild='nixos-rebuild switch'
alias rebuild-dry='nixos-rebuild dry-activate'
alias rebuild-rollback='nixos-rebuild switch --rollback'

# Secrets
alias secrets-edit='sops hosts/core-pi/secrets.yaml'
alias secrets-view='sops -d hosts/core-pi/secrets.yaml'
```

---

## Emergency Contact

If something is broken and you're stuck:
1. Check `docs/TROUBLESHOOTING.md` (symptom → diagnosis)
2. Run `./tools/fleet-health-check.sh` (system state)
3. Check `journalctl` on affected device
4. Review recent commits (`jj log -n 5`)
5. Rollback if needed (`jj revert <hash>`)

---

**Last Updated:** 2026-08-17  
**For details:** See related documentation linked above
