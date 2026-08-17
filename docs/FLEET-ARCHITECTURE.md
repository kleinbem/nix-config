# Fleet Architecture Overview

**Status:** Complete reference to the kleinbem fleet structure  
**Updated:** 2026-08-17

High-level architecture and integration guide for the entire kleinbem infrastructure fleet.

---

## The Fleet at a Glance

```
                       kleinbem Fleet (2026-08-17)
                      ══════════════════════════════

CONDUCTOR REPOS (Meta-orchestrators)
├─ nix/                    (Nix/NixOS orchestrator)
├─ openwrt/                (Router orchestrator)
└─ kleinbem/               (Fleet hub, repos.nix, jj-fleet)

NIXOS REPOS (Real work happens here)
├─ nix-config              (NixOS configs: hosts, modules, users)
├─ nix-devshells           (Dev environments, pre-commit hooks)
├─ nix-presets             (Reusable service/desktop bundles)
├─ nix-hardware            (Hardware profiles, device quirks)
├─ nix-packages            (Custom package overlays)
├─ nix-templates           (Flake templates for new projects)
└─ kleinbem-secrets        (Encrypted fleet secrets: sops+age)

OPENWRT REPOS
├─ openwrt-builder         (OpenWrt firmware: BPI-R4 release)
├─ openwrt-config          (Runtime config: Ansible playbooks)
└─ openwrt-secrets         (OpenWrt encrypted secrets)

META REPOS
├─ github-config           (Terraform: org settings, rulesets)
├─ kleinbem-site           (Astro site: kleinbem.dev)
└─ nix-secrets (legacy)    (Superseded by kleinbem-secrets)
    openwrt-secrets        (Superseded by kleinbem-secrets)
```

---

## Device Deployment Matrix

```
Tier                Devices              Deployment     Config Repo
────────────────────────────────────────────────────────────────────
Workstation         nixos-nvme           Local (ssh)     nix-config
                    mac-mini             SSH             nix-config

Edge Hub            core-pi              SSH + auto-upg  nix-config
                    (always online)

Edge Nodes          orin-nano            SSH             nix-config
                    nasbook              SSH             nix-config
                    hass-pi              SSH (planned)   nix-config

Mobile              phone (Android)      Nix on Droid    nix-config
                    (local only)

Routers             core-gateway         Ansible         openwrt-config
                    ap-upstairs          Ansible         openwrt-config
```

---

## Repository Relationships

### Data Flow

```
                          git commit
                             ↓
                    GitHub (kleinbem org)
                             ↓
                    GitHub Actions (CI)
                             ↓
                    Attic cache (core-pi)
                             ↓
                Devices (pull + activate)
```

### Dependency Graph

```
nix-config (primary config)
    ├─ imports: nix-hardware (device quirks)
    ├─ imports: nix-presets (service bundles)
    ├─ imports: nix-devshells (home-manager)
    ├─ imports: nix-packages (overlays)
    ├─ secrets: kleinbem-secrets (encrypted)
    └─ depends: kleinbem-site (reference docs)

nix/ (conductor)
    └─ links to: nix-config, nix-devshells, nix-presets, etc.

openwrt-config (router config)
    ├─ imports: openwrt-builder (firmware)
    └─ secrets: kleinbem-secrets (encrypted)

github-config (GitHub org)
    └─ Terraform-manages: all kleinbem org repos
```

---

## Data Centers & Networking

### Physical Layout

```
LAN: 10.0.0.0/24 (wired infrastructure)
├─ 10.0.0.1    = core-gateway (BPI-R4, main router)
├─ 10.0.0.2    = ap-upstairs (BPI-R4, AP/extender)
├─ 10.0.0.5    = nixos-nvme (workstation, x86_64)
├─ 10.0.0.15   = orin-nano (NVIDIA Jetson, aarch64)
├─ 10.0.0.16   = mac-mini (x86_64, legacy hardware)
├─ 10.0.0.21   = hass-pi (Raspberry Pi 5, aarch64, planned)
├─ 10.0.0.22   = core-pi (Raspberry Pi 5, aarch64, hub)
└─ 10.0.0.30   = nasbook (QNAP NAS, x86_64)

Container Subnets (on each host):
├─ core-pi     → 10.85.48.0/24 (Caddy, ntfy, attic, etc.)
├─ mac-mini    → 10.85.50.0/24 (monitoring, persona runtime)
└─ nasbook     → 10.85.47.0/24 (paperless, backup, etc.)

Mesh Network (NetBird, WireGuard):
├─ All hosts have stable mesh IPs (100.117.X.X range)
├─ Provides: encrypted inter-host communication
└─ Fallback: when LAN routing is unavailable
```

### Internet Boundary

```
Public Internet
        ↓
Cloudflare (DDoS protection, DNS)
        ↓
Cloudflare Tunnel (core-pi)
        ↓
Caddy (reverse proxy)
        ↓
Container Network
        ↓
Internal Services
```

---

## Configuration Hierarchy

### By Device Type (Tiers)

```
All Devices
    ↓
Tier-Specific Base
├─ Workstation (base.nix → workstation.nix)
├─ Edge Hub (rpi5-node.nix → base.nix + headless.nix)
├─ Edge Node (base.nix + headless.nix + role-specific)
└─ Mobile (minimal: nix + ca-certs)
    ↓
Device-Specific Customization
```

### By Function

```
Shared Modules
├─ base.nix               (users, ssh, security)
├─ networking.nix        (interfaces, firewall)
├─ hardening.nix         (selinux, apparmor, audit)
├─ persistence.nix       (impermanence setup)
├─ clevis-initrd.nix     (encrypted boot)
├─ container-host.nix    (container networking, auto-update)
├─ desktop.nix           (GNOME, GUI apps)
├─ audio.nix             (pipewire, ALSA)
├─ dev.nix               (development tools)
└─ + 20+ more specialized modules

Home-Manager Modules
├─ git configuration
├─ terminal setup
├─ VSCode configuration
├─ security tools
└─ + 15+ user-specific modules
```

---

## Secrets Management

### Encryption Strategy

```
Plaintext Secret (in memory, never on disk)
    ↓
age encryption (lightweight, modern)
    ↓
sops YAML file (human-readable encrypted format)
    ↓
Git commit (encrypted file safe to push)
    ↓
NixOS evaluation (decrypt via age key)
    ↓
/run/secrets/* (ephemeral, cleaned on reboot)
    ↓
Service/container access (environment variable or file path)
```

### Key Distribution

```
YubiKey (SSH FIDO2)
    ├─ Used for: git signing, deployments
    └─ Location: with user (personal device)

age private key (~/.config/sops/age/keys.txt)
    ├─ Used for: local sops decryption
    ├─ Location: on each device
    └─ Backup: encrypted USB drive (annual)

SSH host keys
    ├─ Used for: decrypt at activation time
    └─ Location: /etc/ssh/ssh_host_*_key
```

---

## Deployment Pipeline

### Local Development

```
Edit config
    ↓
`nix eval` (syntax check)
    ↓
`nixos-rebuild build` (build locally)
    ↓
Test on workstation (if applicable)
    ↓
Review with `jj diff`
    ↓
`jj describe` (create commit, signs via YubiKey)
```

### Push to GitHub

```
`jj git push` (pushes to GitHub)
    ↓
GitHub branch: main (requires signed commits)
    ↓
CI runs (if workflows configured)
    ↓
Ready for deployment
```

### Device Deployment

```
Phase 1: Edge Testing (orin-nano)
    ↓
Phase 2: Non-Critical (nasbook, hass-pi)
    ↓
Phase 3: Production (core-pi, mac-mini)
    ↓
Phase 4: Gateway (core-gateway, ap-upstairs)
    ↓
Rollback ready (at each phase)
```

---

## Service Distribution

### By Device

```
nixos-nvme (Workstation)
├─ Desktop (GNOME)
├─ Development tools (nixvim, VSCode)
├─ Containers (various experimental)
├─ GitHub runner (CI builds)
└─ Home-Manager (full setup)

core-pi (Edge Hub)
├─ Caddy (reverse proxy, edge entry point)
├─ Attic (binary cache, critical infrastructure)
├─ ntfy (push notifications, deploy signal)
├─ crowdsec (intrusion detection)
├─ authelia (SSO gateway)
├─ dashboard (landing page)
├─ container-updater (nightly container refresh)
└─ + 5-10 more containers

mac-mini (Desktop + Monitoring)
├─ GNOME Remote Desktop (GUI access)
├─ monitoring (Prometheus exporter + Grafana) [moved from core-pi 2026-08-05]
├─ persona-runtime (AI agents, multi-user)
├─ Open WebUI (LLM chat interface)
└─ + containers for monitoring/obs

nasbook (NAS + Data)
├─ Paperless (document management)
├─ agent-team (team collaboration tools)
├─ syncthing (file sync)
├─ backup (restic, rclone)
├─ qdrant (vector database)
└─ loki (log aggregation)

orin-nano (AI Edge)
├─ AI inference workloads
├─ Jetson-specific optimizations
├─ Low-power optimization
└─ Experimental containers

core-gateway (Router)
├─ OpenWrt (BPI-R4 firmware)
├─ WireGuard (VPN, mesh)
├─ DHCP/DNS
├─ Firewall (nftables)
└─ VLAN management

ap-upstairs (Wireless AP)
├─ 5GHz/2.4GHz Wi-Fi
├─ VLAN bridges
└─ Mesh coordination (WireGuard)
```

---

## Build & Cache System

### Local Builds

```
Developer
    ↓
`nixos-rebuild build` (local machine)
    ↓
Derivations evaluated (flake.nix + inputs)
    ↓
Store paths (/nix/store/...)
    ↓
Ready to deploy
```

### Cache Workflow (Attic)

```
CI (GitHub Actions)
    ↓
Build all device configs
    ↓
Push to Attic cache (core-pi)
    ↓
Devices pull from cache (faster than rebuilding)
    ↓
container-updater pulls container images nightly
```

### Fallback Chain

```
Try: Attic cache (fast)
    ↓
Fall back to: substituters in nix.conf
    ↓
Fall back to: build locally (slow, CPU intensive)
```

---

## Home-Manager Integration

### User Provisioning

```
Users defined in:
├─ users/martin/   (primary)
├─ users/dhirujaan/ (secondary)
├─ users/juan/
├─ users/michael/
└─ + others (stubs)

Each has:
├─ nixos.nix (NixOS-level config)
└─ home.nix (Home-Manager config)

Applied when:
├─ Device includes: `${self}/users/martin/nixos.nix`
└─ Device sets: `home-manager.users.martin = { imports = [...]; };`
```

### Home-Manager Modules

```
home-manager/default.nix (aggregator, like nixos/default.nix)
├─ dev.nix (development environment)
├─ vscode.nix (VSCode setup)
├─ nixvim.nix (Neovim config)
├─ security.nix (security tools)
├─ syncthing.nix (file sync)
├─ workspace-guardian.nix (productivity)
└─ + from nix-presets (git, terminal, firefox, etc.)
```

---

## Monitoring & Observability

### Current Setup (as of 2026-08-17)

```
Moved from core-pi to mac-mini (2026-08-05 due to RAM pressure)

Monitoring Container (mac-mini)
    ├─ Prometheus (metrics collection)
    ├─ Grafana (visualization)
    └─ Scrapes targets:
        ├─ nixos-nvme (node exporter)
        ├─ core-pi (node exporter)
        ├─ orin-nano (node exporter)
        ├─ nasbook (node exporter)
        ├─ core-gateway (snmp)
        └─ ap-upstairs (snmp)

Logging Stack (nasbook)
    ├─ Loki (log aggregation)
    └─ Scrapes: all device logs
```

---

## Cross-Repo Coordination

### repos.nix (Single Source of Truth)

Located: `kleinbem/repos.nix`

Defines:
```nix
{
  "nix-config" = {
    url = "github:kleinbem/nix-config";
    branch = "main";
  };
  "openwrt-config" = { ... };
  # ... every repo in the fleet
}
```

Used by:
- `jj-fleet.sh` (fleet-wide commands)
- `just status-all` (see all repos)
- CI/CD (orchestrate across repos)
- Bootstrapping (`just bootstrap`)

### Fleet Commands

```bash
# From any repo in workspace:
just status-all              # See all repos + uncommitted changes
just diff-all                # See diffs across fleet
just remote-ci               # Check CI status GitHub-wide
just push-all                # Push all repos
just sign-unsigned           # Sign all unsigned commits
just ship-all "msg"          # Save + sign + push all at once
```

---

## Integration Patterns

### Inputs (Dependencies on Other Repos)

```nix
# nix-config flake.nix
inputs.nix-hardware = {
  url = "github:kleinbem/nix-hardware";
  inputs.nixpkgs.follows = "nixpkgs";
};

inputs.nix-presets = {
  url = "github:kleinbem/nix-presets";
  inputs.nixpkgs.follows = "nixpkgs";
};

# nix-presets flake.nix
inputs.nix-devshells = {
  url = "github:kleinbem/nix-devshells";
  inputs.nixpkgs.follows = "nixpkgs";
};
```

### Version Coordination

```
nixpkgs version pinned in: nix-devshells/flake.nix (source of truth)
↓
All other repos follow via: inputs.nixpkgs.follows = "nixpkgs"
↓
Synchronized across fleet
↓
CI audit-versions detects drift
```

---

## Safe Change Patterns

### Adding a New Device

```
1. Add to inventory.nix (this repo)
2. Create hosts/<device>/ directory
3. Follow DEVICE-TIERS.md template
4. Deploy: Phase 1 → Phase 2 → Phase 3 → Phase 4
5. Update device roster (DEVICE-TIERS.md status matrix)
```

### Adding a New Service

```
1. Create in nix-presets (if reusable) or nix-config (if one-off)
2. Define sops.secrets (if needed)
3. Test locally: nixos-rebuild build
4. Deploy to edge device first (orin-nano)
5. Roll out per DEPLOYMENT-STRATEGY.md
```

### Rotating Secrets

```
1. Edit sops file: sops hosts/<device>/secrets.yaml
2. Change value
3. Commit: jj describe -m "chore: rotate X credentials"
4. Deploy immediately: nixos-rebuild switch
5. Verify in logs that new credentials work
```

---

## Disaster Recovery

### If Core-Pi Down (Cache Lost)

```
1. Devices can't pull from cache
2. Build locally (slow, CPU-intensive)
3. Set substituters = [] in nix.conf (force local)
4. Recover core-pi from backup
```

### If Gateway Down (No Internet)

```
1. Mesh network still works (NetBird)
2. Internal communication unaffected
3. External services unreachable (until recovered)
4. Boot to recovery/serial console
5. Restore from OpenWrt backup
```

### If NixOS Config Broken

```
1. Boot to previous generation (automatic on failure)
2. Or: jj revert <bad-commit> + nixos-rebuild switch
3. Rollback procedure documented in DEPLOYMENT-STRATEGY.md
```

---

## Documentation Map

| Document | Purpose | Audience |
|----------|---------|----------|
| DEVICE-TIERS.md | Tier definitions & setup | New maintainers |
| MODULE-ORGANIZATION.md | Module patterns | Developers |
| CONTAINER-HOST-SETUP.md | Container hosting | Ops, developers |
| TROUBLESHOOTING.md | Diagnostics | Operators |
| SECRETS-MANAGEMENT.md | Secure secrets | Security-conscious maintainers |
| DEPLOYMENT-STRATEGY.md | Safe rollout | Release engineers |
| FLEET-ARCHITECTURE.md | System overview | All (this doc) |

---

## Key Design Principles

1. **Jj-first VCS** — All commits signed, auditable history
2. **Declarative infrastructure** — NixOS + Terraform for all config
3. **Phased deployment** — Edge → non-critical → production → gateway
4. **Secrets encrypted at rest** — sops + age, decrypted only at activation
5. **Cache-first builds** — Attic for fast deployments
6. **Self-healing rollback** — Previous generation always available
7. **Cross-repo coordination** — repos.nix as single source of truth
8. **Documented operations** — Procedures for all common tasks

---

**Last Updated:** 2026-08-17  
**Status:** Complete overview of fleet structure  
**Audience:** All fleet members, new maintainers, operators
