# Fleet Troubleshooting & Diagnostics Guide

**Status:** Troubleshooting guide for common kleinbem fleet issues  
**Updated:** 2026-08-17

Quick reference for diagnosing and resolving issues in the kleinbem NixOS infrastructure.

---

## 🔍 Diagnostic Checklist

Before troubleshooting, gather information:

```bash
# Device status
jj status
jj log -n 5  # Recent commits

# System state
systemctl status
systemctl list-failed

# Hardware
lsblk                  # Disk/partition state
nix-tree               # Dependency graph

# Network
ip addr show           # Network interfaces
ss -tlnp               # Listening ports
systemctl status NetworkManager

# Flakes
nix flake info
nix flake show .#<host>

# Containers (if applicable)
machinectl list
systemctl list-units --state=failed | grep container
```

---

## Network & Connectivity Issues

### Issue: SSH Connection Refused / Timeout

**Symptoms:** `ssh <host>` hangs or fails with "Connection refused"

**Diagnosis:**
```bash
# 1. Check host is reachable
ping 10.0.0.XX          # LAN IP from inventory

# 2. Check SSH is listening
nmap -p 22 10.0.0.XX    # Or: nc -zv 10.0.0.XX 22

# 3. Check firewall
sudo nft list ruleset | grep tcp
ssh -vvv user@host      # Verbose output

# 4. On the host, check SSH service
systemctl status ssh
systemctl status sshd   # Or whatever your SSH service is named

# 5. Check SSH key
ssh-add -l              # Loaded keys
cat ~/.ssh/authorized_keys  # On remote
```

**Solutions:**

| Cause | Fix |
|-------|-----|
| Host offline | Power on device, check LAN connectivity |
| SSH not listening | `systemctl restart ssh` |
| Firewall blocking | Check `networking.firewall.allowedTCPPorts` in config |
| Wrong key | Verify SSH key in inventory.nix or users/*/nixos.nix |
| firewall.enable = true but no rules | Add SSH port: `allowedTCPPorts = [ 22 ]` |

---

### Issue: "Permission denied (publickey)" after Deploy

**Symptoms:** Deploy succeeds, but subsequent SSH fails

**Cause:** SSH keys not propagated properly

**Diagnosis:**
```bash
# On your machine
ssh-add -l              # What keys are loaded?

# On remote (via serial/console)
cat /home/martin/.ssh/authorized_keys
ls -la /home/martin/.ssh/

# Check deployment added keys
grep "openssh.authorizedKeys" hosts/<device>/default.nix
```

**Solutions:**

1. **Re-deploy with correct keys:**
   ```bash
   cd nix-config
   just nixos::deploy-<device>
   ```

2. **Manual fix (via console/serial):**
   ```bash
   sudo cat /etc/ssh/ssh_host_*_key.pub  # Check host keys
   ssh-copy-id -i ~/.ssh/id_ed25519.pub martin@<device>
   ```

3. **Check users config:**
   ```nix
   users.users.martin.openssh.authorizedKeys.keys = [
     # Make sure your key is here
   ];
   ```

---

### Issue: DNS Not Resolving

**Symptoms:** Can reach hosts by IP, but hostnames fail

**Diagnosis:**
```bash
# Check resolvers
cat /etc/resolv.conf

# Test resolution
nslookup google.com
dig @10.85.48.1 cache.kleinbem.dev    # Check internal DNS

# On container hosts
systemctl status systemd-resolved      # Or dnsmasq
ss -tlnp | grep 53                    # Check if DNS listening
```

**Solutions:**

1. **System resolver not working:**
   ```bash
   systemctl restart systemd-resolved
   ```

2. **Internal domain (cache.kleinbem.dev) not resolving:**
   - Check if Caddy is running (core-pi)
   - Check if DNS proxy is configured
   - Manually add to /etc/hosts (temporary)

---

## Storage & Persistence Issues

### Issue: /nix/persist Not Being Persisted

**Symptoms:** Data disappears after reboot (impermanent system)

**Diagnosis:**
```bash
# Check if impermanence is enabled
grep -r "impermanence" hosts/<device>/
nix eval .#nixosConfigurations.<device>.config.environment.persistence

# Check what's persisted
ls -la /nix/persist/

# Check disk space
df -h
du -sh /nix/persist/*

# Check systemd mount
systemctl status bindfs@nix-persist  # If using bindfs
mount | grep persist
```

**Solutions:**

1. **Not persisting (should be but isn't):**
   - Add path to `environment.persistence`:
   ```nix
   environment.persistence."/nix/persist" = {
     directories = [ "/path/to/data" ];
   };
   ```

2. **Disk full:**
   ```bash
   sudo du -sh /nix/persist/*  # Find largest dirs
   sudo ncdu /nix/persist/     # Interactive explorer
   ```

3. **Wrong mount point:**
   - Verify persistence target in disko.nix
   - Check if /nix/persist is mounted: `mount | grep persist`

---

### Issue: Container Data Lost After Reboot

**Symptoms:** Container state/database gone after reboot

**Diagnosis:**
```bash
# Check container persistence config
grep hostDataDir hosts/<device>/default.nix

# Verify directory is in persistence config
nix eval .#nixosConfigurations.<device>.config.environment.persistence

# Check where container data is actually stored
machinectl list
systemctl status container@<name>
systemctl show -p RootDirectory container@<name>

# Check if directory exists on disk
ls -la /var/lib/images/<container>/
```

**Solutions:**

1. **Container not in persistence config:**
   ```nix
   environment.persistence."/nix/persist" = {
     directories = [
       "/var/lib/images/<container>"  # ADD THIS
     ];
   };
   ```

2. **Container-updater is resetting state:**
   - Add to `excludeFromUpdater` if it's critical
   - Or ensure backup strategy for stateful containers

---

## Deployment & Build Issues

### Issue: NixOS Rebuild Fails / Eval Error

**Symptoms:** `nixos-rebuild switch` fails, cryptic eval error

**Diagnosis:**
```bash
# Get more details
nixos-rebuild build 2>&1 | head -50

# Check flake
nix flake show --all-systems

# Validate specific config
nix eval .#nixosConfigurations.<device>.config.system.build.toplevel

# Check for typos in imports
grep imports hosts/<device>/default.nix
```

**Common Causes:**

| Error | Fix |
|-------|-----|
| `undefined variable 'foo'` | Module not imported, or typo |
| `attribute 'x' missing` | Required option not set |
| `infinite recursion` | Circular module dependency |
| `out of memory` | Disable/reduce binary caching, rebuild locally |

**Solutions:**

1. **Check recent changes:**
   ```bash
   git diff HEAD~1   # What changed?
   git log --oneline -5
   ```

2. **Rollback to last working:**
   ```bash
   git revert HEAD
   ```

3. **Minimal test:**
   ```bash
   nix eval .#nixosConfigurations.<device>.config.system.nixos.version
   ```

---

### Issue: Binary Cache Not Working / Slow Builds

**Symptoms:** Even simple things rebuild from source, very slow

**Diagnosis:**
```bash
# Check cache connectivity
nix-shell -p curl --run "curl https://cache.kleinbem.dev/nix-cache-info"

# Check local cache
ls /nix/store | head -5

# Monitor build
watch -n 1 'ps aux | grep nix-build'

# Check Attic (if deployed)
curl http://10.85.48.120:8080/v2/_catalog  # Attic container IP
```

**Solutions:**

1. **Cache unreachable:**
   - Ensure Caddy/core-pi is online
   - Check firewall rules
   - Verify DNS resolution

2. **Network slow:**
   - Check bandwidth: `iperf3 -c <cache-host>`
   - Use NetBird for large transfers

---

## Container Issues

### Issue: Container Won't Start / Fails to Deploy

**Symptoms:** `systemctl start container@<name>` fails

**Diagnosis:**
```bash
# Check systemd status
systemctl status container@<name>
journalctl -u container@<name> -n 50  # Recent logs

# Check image availability
machinectl list-images
systemctl status systemd-nspawn  # Underlying service

# Check network
systemctl status systemd-network

# Manual container test
systemd-nspawn -i <image> /bin/bash
```

**Solutions:**

1. **Image not found:**
   - Check if container preset is imported
   - Pull from cache: `systemctl restart services-container-updater`

2. **Port conflict:**
   - Check if port is already in use: `ss -tlnp | grep :<port>`
   - Change container IP in config

3. **Secrets missing:**
   - Verify sops decryption ran
   - Check `config.sops.secrets.<name>.path` exists

---

### Issue: Container Can't Reach External Network / Other Containers

**Symptoms:** Container A can't ping container B, or can't reach internet

**Diagnosis:**
```bash
# From container
machinectl shell <container>
ping 8.8.8.8             # External
ping 10.85.48.X          # Other container
ip addr show             # Check container IP
ip route show            # Check routes

# From host
ip link show             # Check bridge (cbr0)
nft list ruleset | grep cbr0
nft list ruleset | grep forward
```

**Solutions:**

1. **Firewall blocking:**
   - Check `extraForwardRules` in config
   - Add rules for container traffic

2. **Wrong subnet:**
   - Verify container IP is in correct subnet
   - Check bridge configuration

3. **NAT issues (NetBird):**
   - Check if PREROUTING rules are correct
   - Verify NAT translation with `nft trace`

---

## Secrets & Encryption Issues

### Issue: Sops Decryption Fails / "Permission Denied"

**Symptoms:** `sops.secrets.<name>` shows "cannot decrypt"

**Diagnosis:**
```bash
# Check sops file exists
ls -la /run/secrets/<name>

# Verify age/gpg key is available
age-keygen -l ~/.config/sops/age/keys.txt
gpg --list-secret-keys

# Check sops.yaml configuration
cat .sops.yaml
grep -A5 "<host>" .sops.yaml

# Test decryption manually
sops -d nix-secrets/nix/shared.yaml | head -5
```

**Solutions:**

1. **Age key missing:**
   - Ensure age key is in `~/.config/sops/age/keys.txt`
   - Check permissions: `chmod 600 ~/.config/sops/age/keys.txt`

2. **YubiKey required but unavailable:**
   - Check if age-plugin-yubikey is being used
   - Use fallback SSH key for CI

3. **Secret not in file:**
   - Verify secret exists in sops file
   - Add it: `sops nix-secrets/nix/shared.yaml` → add key

---

### Issue: Secrets Accessible But Shouldn't Be / Security Issue

**Symptoms:** Unencrypted secrets in /run/secrets/, or wrong permissions

**Solutions:**

1. **Verify permissions:**
   ```bash
   ls -la /run/secrets/
   # Should be: -rw------- root root (600, owned by process)
   ```

2. **Check sops-install-secrets ran:**
   ```bash
   systemctl status sops-install-secrets
   journalctl -u sops-install-secrets -n 20
   ```

3. **Audit what's exposed:**
   ```bash
   find /run/secrets -type f
   strings /run/secrets/* | grep -i "password\|token\|key"
   ```

---

## Performance Issues

### Issue: System Slow / High CPU / Memory Pressure

**Diagnosis:**
```bash
# System load
top -b -n 1

# Memory
free -h
vmstat 5 5

# Disk I/O
iotop -b -n 1

# Process tree
ps auxf | head -20

# Nix-related
ps aux | grep nix-
du -sh /nix/{store,var}
```

**Common Causes & Fixes:**

| Cause | Fix |
|-------|-----|
| Nix GC needed | `nix-collect-garbage -d` |
| Container OOM | Increase memoryLimit, check processes inside |
| Disk full | `du -sh /nix/store/*` → find large packages |
| Evaluator spinning | Stop `nix eval`, check for infinite recursion |
| High ZFS compression | Use `compress=zstd:1` (lower compression) |

---

## Monitoring & Observability

### Issue: Monitoring Not Working / Grafana Down

**Diagnosis:**
```bash
# Monitoring moved to mac-mini (see memory)
systemctl status monitoring  # If local
systemctl status prometheus
systemctl status grafana

# If on mac-mini
ssh mac-mini "systemctl status monitoring"

# Check if metrics are being scraped
curl http://10.85.48.106:9090/targets  # Prometheus IP
```

**Solutions:**

1. **Monitoring container not running:**
   ```bash
   machinectl start monitoring  # Or container@monitoring
   ```

2. **Scrape targets down:**
   - Check Prometheus config for target IPs
   - Verify hosts are reachable

---

## Still Stuck?

### Debug Steps

1. **Get full context:**
   ```bash
   jj log -n 10                    # Recent history
   nix flake show --all-systems    # Flake state
   systemctl status --failed       # Failed units
   journalctl -xe -n 30            # Full journal
   ```

2. **Search fleet for similar issue:**
   ```bash
   grep -r "error-text" hosts/
   grep -r "error-text" modules/
   ```

3. **Check related docs:**
   - DEVICE-TIERS.md — Device roles & requirements
   - MODULE-ORGANIZATION.md — Module patterns
   - CONTAINER-HOST-SETUP.md — Container troubleshooting
   - CI-HARDENING-RECOMMENDATIONS.md — CI/automation issues

4. **Create minimal reproduction:**
   - Comment out recent changes
   - Test on a different host
   - Isolate to one module

---

## Reporting Issues

When reporting a bug, include:

```
Device: <name from inventory.nix>
Role: <tier from DEVICE-TIERS.md>
Symptom: <what happened>
Diagnostic output:
  - jj log -n 5
  - systemctl list-failed
  - journalctl -xe -n 30
Recent changes:
  - git diff HEAD~3..HEAD
Environment:
  - nix --version
  - jj --version
```

---

## Related Resources

- **Architecture:** DEVICE-TIERS.md, MODULE-ORGANIZATION.md
- **Containers:** CONTAINER-HOST-SETUP.md
- **Secrets:** (in progress, see TODO)
- **CI/CD:** kleinbem/docs/MAINTENANCE-AUTOMATION.md
- **Audit:** (scratchpad) FLEET-INFRA-AUDIT.md

---

**Last Updated:** 2026-08-17  
**Status:** Active (add new issues as discovered)
