# Deployment & Upgrade Strategy

**Status:** jj-first fleet, signed commits, distributed deployment  
**Updated:** 2026-08-17

Guide to safely deploying configuration changes across the kleinbem fleet.

---

## Overview

The kleinbem fleet uses a **phased deployment strategy** to minimize risk:

1. **Local Testing** (workstation, evaluate)
2. **Edge Testing** (orin-nano, safe to break)
3. **Non-Critical Infrastructure** (hass-pi, nasbook)
4. **Production** (core-pi, mac-mini)
5. **Critical Gateway** (core-gateway, last)

```
Dev Change
    ↓
Git/jj commit (local)
    ↓
Push to GitHub
    ↓
CI tests (if applicable)
    ↓
Deploy to Test Tier (evaluate + orin-nano)
    ↓
Deploy to Non-Critical (hass-pi, nasbook)
    ↓
Deploy to Production (core-pi, mac-mini)
    ↓
Verify (monitoring, logging, tests)
    ↓
Deploy to Gateway (last, lowest tolerance for downtime)
```

---

## VCS Workflow (jj-first)

### Branching Model

**Current state:** jj colocated with git, all work on `main` (no traditional branching)

```bash
# Local changes are in the working copy
jj status

# Create a named snapshot
jj describe -m "feat: add new module"

# See draft commits
jj log -n 5

# Ready to push
jj git push  # Requires YubiKey signature
```

### Commit Requirements

- ✅ **Signed commits** (YubiKey SSH FIDO2)
- ✅ **Descriptive messages** (what + why, not just what)
- ✅ **Atomic commits** (one logical change per commit)
- ✅ **Tested locally** (before pushing)

### Commit Message Format

```
<type>: <subject (50 chars max)>

<body (72 chars per line)>
<explain what and why, not how>

<references>
Fixes #123
Related to: docs/DEVICE-TIERS.md

Co-Authored-By: ...
```

Examples:
```
feat: add container-host module for simplified setup

Reduces per-device boilerplate by 50+ lines. Handles networking,
persistence, and container-updater orchestration. Existing hosts
can migrate incrementally (non-breaking).

Ref: FLEET-INFRA-AUDIT.md Gap #2
```

```
fix: disable waypipe on aarch64-linux

FFmpeg 9.0 API changes break waypipe build on aarch64. Disabling
on non-desktop architectures (orin-nano, core-pi, hass-pi are
headless anyway). x86_64 workstations unaffected.

Fixes: Build failures on aarch64 CI
```

---

## Local Testing Before Deployment

### 1. Evaluate Configuration

```bash
# Syntax check
nix eval .#nixosConfigurations.<device>.config.system.nixos.version

# Check for eval errors (detailed)
nix eval .#nixosConfigurations.<device>.config.services.openssh

# Dry-run build (no instantiation)
nix build .#nixosConfigurations.<device>.config.system.build.toplevel \
  --no-link --dry-run
```

### 2. Test on Workstation (if applicable)

```bash
# For changes to desktop environment, home-manager, etc.
nixos-rebuild build

# Check for warnings
nixos-rebuild build 2>&1 | grep -i "warning\|error"

# Test functionality
# - Launch GUI apps
# - Check desktop settings
# - Verify containers start
```

### 3. Review Changes

```bash
# What changed?
jj diff HEAD~1

# Check affected devices
grep -l "the_module_I_changed" hosts/*/default.nix
grep -l "the_option_I_added" modules/nixos/*.nix

# Estimate blast radius
# - Desktop-only changes? Low risk
# - Core module (base.nix)? High risk
# - One device? Low impact
```

---

## Deployment Phases

### Phase 0: Local + GitHub

```bash
# 1. Commit locally
jj describe -m "fix: ..."

# 2. Push to GitHub
jj git push  # Requires YubiKey

# 3. CI runs (if configured)
gh run list --repo kleinbem/nix-config

# 4. Get approval (self-review, code review if pairing)
```

### Phase 1: Edge Testing (orin-nano)

**Device:** orin-nano (safe to break, low impact if offline)  
**Approach:** SSH deploy

```bash
cd nix-config

# 1. Dry-run
nixos-rebuild dry-activate -h 10.0.0.15

# 2. Build on device (or substitute from cache)
nixos-rebuild build -h 10.0.0.15

# 3. Switch (activate new generation)
nixos-rebuild switch -h 10.0.0.15

# 4. Verify
ssh 10.0.0.15 "nixos-version"
ssh 10.0.0.15 "systemctl status"
```

### Phase 2: Non-Critical Infrastructure (hass-pi, nasbook)

**Devices:** hass-pi (planned, not critical), nasbook (storage, non-critical)  
**Approach:** SSH deploy

```bash
for device in hass-pi nasbook; do
  nixos-rebuild switch -h "10.0.0.21"  # hass-pi
  nixos-rebuild switch -h "10.0.0.30"  # nasbook
done

# Verify
for device in hass-pi nasbook; do
  ssh "10.0.0.XX" "systemctl status"
done
```

### Phase 3: Production (core-pi, mac-mini)

**Devices:** core-pi (cache hub), mac-mini (desktop, monitoring)  
**Approach:** SSH deploy (requires cache working)

```bash
# core-pi: deploy during low-traffic window (2-4 AM UTC)
nixos-rebuild switch -h 10.0.0.22 --fallback

# Verify cache is accessible
curl https://cache.kleinbem.dev/nix-cache-info

# mac-mini: deploy anytime
nixos-rebuild switch -h 10.0.0.16

# Verify critical services
ssh 10.0.0.22 "systemctl status caddy container-updater"
ssh 10.0.0.16 "systemctl status monitoring"
```

### Phase 4: Gateway (core-gateway, ap-upstairs)

**Devices:** core-gateway (main router), ap-upstairs (AP)  
**Approach:** OpenWrt config push (different workflow)

```bash
cd openwrt-config

# 1. Ansible dry-run
ansible-playbook playbooks/deploy.yaml --check

# 2. Deploy
ansible-playbook playbooks/deploy.yaml

# 3. Verify connectivity
ping 10.0.0.1   # core-gateway
ssh 10.0.0.2    # ap-upstairs

# 4. Check mesh
# Verify all nodes see each other
```

---

## Automated Deployment (CI)

### Promote-Production Workflow

Current setup uses GitHub Actions to:
1. Build all configs in parallel
2. Push to cache (Attic)
3. Signal devices to upgrade nightly

```bash
# Triggers: push to main, manual dispatch
# Runs: Every push
# Action: publish new containers + host closures to Attic

# Devices subscribe via:
#   - auto-upgrade.nix (regular nixos-rebuild)
#   - container-updater.service (nightly refresh)
```

### CI Checks

```yaml
# .github/workflows/ci.yaml (if it exists)
- lint (statix, deadnix, nixfmt)
- build (nixos-build for each device)
- test (if test suite exists)
```

Run before merging to main:
```bash
nix flake check
```

---

## Rollback Procedure

### Quick Rollback (Last Boot Failed)

```bash
# Boot menu → select previous generation
# (automatic on first boot failure)

# Or manually
nix-env --list-generations
nix-env --switch-generation 123

# Verify
nixos-version
```

### Config Rollback (Bad Recent Commit)

```bash
# 1. Identify bad commit
jj log -n 10

# 2. Revert it
jj revert <commit-hash>
jj describe -m "Revert bad commit"

# 3. Deploy
jj git push
nixos-rebuild switch

# 4. Verify
systemctl status
```

### Data Rollback (Corrupted Secrets/Config)

```bash
# From git history
git show HEAD~1:hosts/<device>/secrets.yaml | sops -d | head

# Or from backup
cd /encrypted-backup
sops -d kleinbem-secrets/hosts/<device>/secrets.yaml
```

---

## Deployment Checklist

### Before Starting

- [ ] All changes committed and signed
- [ ] CI passing (if applicable)
- [ ] Local evaluation successful (`nix eval`)
- [ ] No emergency maintenance in progress
- [ ] Core-pi has free disk space (`df -h /var/lib/images`)

### Phase 1 (Edge Testing)

- [ ] orin-nano: dry-run successful
- [ ] orin-nano: systemctl status shows no failures
- [ ] orin-nano: test the changed feature
- [ ] orin-nano: revert if issues

### Phase 2 (Non-Critical)

- [ ] nasbook: deploy + verify
- [ ] hass-pi: deploy + verify (if deployed)
- [ ] Both: systemctl list-failed shows no new failures

### Phase 3 (Production)

- [ ] core-pi: off-peak deployment (2-4 AM UTC)
- [ ] core-pi: cache working (`curl nix-cache-info`)
- [ ] core-pi: containers healthy (`machinectl list`)
- [ ] mac-mini: deploy + verify
- [ ] Monitoring shows no alerts

### Phase 4 (Gateway)

- [ ] Gateway deployment during maintenance window
- [ ] All mesh nodes reachable
- [ ] DNS/routing working
- [ ] Internet connectivity verified

---

## Emergency Procedures

### Broken Core-PI (Cache Down)

**Symptom:** All builds fail (cache unreachable)

```bash
# 1. Check core-pi status
ping 10.0.0.22

# 2. If reachable, check services
ssh 10.0.0.22 "systemctl status caddy container@attic"

# 3. Restart cache
ssh 10.0.0.22 "systemctl restart container@attic"

# 4. Warm up cache
nix build .#nixosConfigurations.core-pi.config.system.build.toplevel

# 5. Rollback if needed
jj revert <bad-commit>
```

### Broken Main Router (No Internet)

**Symptom:** No external connectivity

```bash
# 1. Check gateway status
ping 10.0.0.1

# 2. Console access required (serial/physical)
# Use recovery boot if available

# 3. Rollback via OpenWrt UI or CLI
# (restore from backup config)
```

### Cascading Failures

**Symptom:** Multiple devices failing after deploy

```bash
# 1. STOP: Don't deploy to more devices

# 2. Analyze
git log --oneline -n 5
jj diff HEAD~1

# 3. Revert bad commit
jj revert <bad-commit>
jj git push

# 4. Rollback all affected devices (Phase 1-3)
for device in orin-nano nasbook core-pi mac-mini; do
  ssh "10.0.0.XX" "nixos-rebuild switch --rollback"
done

# 5. Post-mortem
# What caused cascading failures?
# - Shared module breaking everything? Split it
# - Bad network config? Add validation
# - Missing secrets? Add checks
```

---

## Safe Defaults for Risky Changes

### Risky: Shared Module Changes

```bash
# ❌ Dangerous: Change base.nix (affects all devices)
# ✅ Safe: 
# 1. Test on orin-nano first
# 2. Manually review diff (all 6 devices affected)
# 3. Have rollback plan ready
# 4. Deploy during office hours (not 2 AM)
```

### Risky: Networking Changes

```bash
# ❌ Dangerous: Change firewall rules without testing
# ✅ Safe:
# 1. Test on non-gateway first (orin-nano)
# 2. Have serial console access to gateway
# 3. Rollback plan: restore from backup
# 4. Deploy during maintenance window
```

### Risky: Secrets Changes

```bash
# ❌ Dangerous: Change sops keys without backup
# ✅ Safe:
# 1. Backup current keys: cp ~/.config/sops/age/keys.txt ~/backup/
# 2. Test decryption: sops -d secrets.yaml
# 3. Deploy to one device first
# 4. Verify in /run/secrets that new secrets appear
```

---

## Monitoring & Verification

### Post-Deployment Checks

```bash
# 1. System state
systemctl status
systemctl list-failed

# 2. Services
systemctl status ssh
systemctl status networking

# 3. If container host
machinectl list
systemctl list-units --all | grep container

# 4. If cache
curl https://cache.kleinbem.dev/nix-cache-info

# 5. If monitoring
curl http://10.85.48.106:9090/api/v1/targets
```

### Alerting Setup

```bash
# Watch for:
# - New systemd failures: `journalctl -p err --since "5 min ago"`
# - Container failures: `machinectl status <name>`
# - Disk pressure: `df -h`
# - Memory pressure: `free -h`
```

---

## Documentation Requirements

### For Each Deploy

- [ ] Commit message explains why (not just what)
- [ ] Affected devices listed (if non-obvious)
- [ ] Test results documented (locally, edge, prod)
- [ ] Rollback plan documented (if risky)

### For Risky Changes

Create an ADR (Architecture Decision Record):
- What changed?
- Why was it needed?
- What alternatives were considered?
- What could go wrong?
- How to rollback?

Example: `docs/ADR-WAYPIPE-PLATFORM-SEPARATION.md`

---

## Related Workflows

- **CI/CD:** `kleinbem/docs/MAINTENANCE-AUTOMATION.md` (audit-versions, checks)
- **Secrets:** `SECRETS-MANAGEMENT.md` (rotation, deployment)
- **Containers:** `CONTAINER-HOST-SETUP.md` (auto-update orchestration)
- **Troubleshooting:** `TROUBLESHOOTING.md` (diagnostics)

---

**Last Updated:** 2026-08-17  
**Status:** Proven strategy, documented for reproducibility  
**Key principle:** Test locally, deploy in phases, rollback ready
