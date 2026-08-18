# Home-Manager Setup Guide

**Status:** Complete reference for user environment configuration  
**Updated:** 2026-08-18

User environment configuration using Home-Manager, covering dev tools, dotfiles, and personal preferences.

---

## Quick Start

### For Existing Users (martin, dhirujaan, etc.)

User home configurations are in `users/<username>/`:

```bash
# View current user config
cat users/martin/home.nix

# Edit and activate
# 1. Modify users/martin/home.nix
# 2. Rebuild: nixos-rebuild switch
# 3. Changes apply at login
```

### Adding a New User

```bash
# 1. Create directory
mkdir -p users/newuser

# 2. Create nixos.nix (NixOS account config)
cat > users/newuser/nixos.nix <<EOF
{ config, lib, ... }:
{
  users.users.newuser = {
    isNormalUser = true;
    home = "/home/newuser";
    shell = lib.mkDefault pkgs.bash;
  };
}
EOF

# 3. Create home.nix (home-manager config)
cat > users/newuser/home.nix <<EOF
{ ... }:
{
  imports = [
    ../../modules/home-manager/default.nix
  ];
  
  home = {
    username = "newuser";
    homeDirectory = "/home/newuser";
    stateVersion = "25.11";
  };
}
EOF

# 4. Add to device config
# In hosts/DEVICE/default.nix:
imports = [ "${self}/users/newuser/nixos.nix" ];
home-manager.users.newuser = { imports = [ "${self}/users/newuser/home.nix" ]; };

# 5. Rebuild
nixos-rebuild switch
```

---

## Module Structure

### Core Modules (`modules/home-manager/`)

| Module | Purpose | Enable |
|--------|---------|--------|
| **default.nix** | Aggregator (all modules below) | Always |
| **gnome.nix** | GNOME desktop setup | `modules.gnome.enable = true` |
| **dev.nix** | Development tools (git, npm, etc.) | `modules.dev.enable = true` |
| **vscode.nix** | VS Code + extensions | `modules.vscode.enable = true` |
| **nixvim.nix** | Neovim configuration | `modules.nixvim.enable = true` |
| **security.nix** | Security tools (age, gpg, sops) | `modules.security.enable = true` |
| **pentesting.nix** | Pentesting tools (Burp, Metasploit) | `modules.pentesting.enable = true` |
| **syncthing.nix** | File sync (now container-based) | `modules.syncthing.enable = false` |
| **workspace-guardian.nix** | Productivity tools | `modules.workspace-guardian.enable = true` |
| **service-launchers.nix** | App launcher integration | `modules.service-launchers.enable = true` |
| **secrets.nix** | Encrypted secrets integration | Auto (via sops) |

### Pattern: Selective Import vs Full Aggregator

**Pattern A — Minimal (New Users)**
```nix
imports = [ "${self}/modules/home-manager/default.nix" ];
modules = { };  # Enable only what's needed
```

**Pattern B — Full Aggregator (Workstations)**
```nix
imports = [ "${self}/modules/home-manager/default.nix" ];
modules = {
  dev.enable = true;
  gnome.enable = true;
  vscode.enable = true;
  security.enable = true;
  workspace-guardian.enable = true;
};
```

---

## Common Customizations

### Add a Development Tool

```nix
# In users/martin/home.nix
home.packages = with pkgs; [
  rustup      # Rust development
  cargo-watch # Auto-build on file changes
  clang       # C/C++ development
];
```

### Configure Git

```nix
# Git is configured in dev.nix, but override in user config:
programs.git = {
  enable = true;
  userName = "Martin";
  userEmail = "martin@example.com";
  extraConfig = {
    core.editor = "nano";
    push.autoSetupRemote = true;
  };
};
```

### Add Shell Alias

```nix
# In users/martin/home.nix
programs.bash.shellAliases = {
  ll = "ls -la";
  deploy = "nixos-rebuild switch -h";
  vi = "nano";
};
```

### Setup SSH Keys

```nix
# SSH keys are managed by NixOS (hosts/*.nix), but shell config:
programs.ssh = {
  enable = true;
  matchBlocks."github.com" = {
    user = "git";
    hostname = "github.com";
    identityFile = "~/.ssh/id_ed25519";
  };
};
```

### Add Firefox Profile

```nix
# Firefox PWA setup (example from martin/home.nix)
my.pwa.enable = true;
my.pwa.apps.bitwarden = {
  name = "Bitwarden";
  url = "https://vault.bitwarden.com";
};
```

---

## Environment Variables

### Setting Variables (Session-Wide)

```nix
home.sessionVariables = {
  EDITOR = "nano";
  BROWSER = "${pkgs.firefox}/bin/firefox";
  # Custom service endpoints
  SERVICE_URL = "https://api.internal";
};
```

### Setting Variables (Bash-Only)

```nix
programs.bash.shellAliases = { };
programs.bash.initExtra = ''
  export RUST_BACKTRACE=1
  export NODE_ENV=development
'';
```

---

## Secrets Integration

### Access Encrypted Secrets

Secrets are encrypted via sops in NixOS, but Home-Manager can access them:

```nix
# In hosts/nixos-nvme/secrets.nix (NixOS level)
sops.secrets.github_token = {
  owner = "martin";
  path = "/home/martin/.config/gh/token";
};

# Then in users/martin/home.nix:
# Secret automatically placed at ~/.config/gh/token at activation
home.file.".config/gh/token" = {
  source = config.sops.secrets.github_token.path;
};
```

### Example: API Key Secret

```nix
# NixOS level (hosts/device/secrets.nix)
sops.secrets.service_api_key = {
  owner = config.my.username;
  path = "/run/secrets/service_api_key";
};

# Home-Manager level (users/username/home.nix)
home.sessionVariables.SERVICE_API_KEY = 
  "$(cat /run/secrets/service_api_key)";
```

---

## Dotfiles Management

### Option 1: Direct Configuration (Recommended)

Define everything in Home-Manager modules:

```nix
# Most common tools have Home-Manager modules
programs.git.enable = true;
programs.vim.enable = true;
programs.zsh.enable = true;
```

### Option 2: Configuration Files

For tools without modules:

```nix
home.file.".config/tool/config.toml".text = ''
  [section]
  key = "value"
'';
```

### Option 3: Source External Files

```nix
home.file.".config/app/config".source = 
  ./dotfiles/app_config;
```

---

## Troubleshooting

### "Module option XYZ does not exist"

**Problem:** Trying to set an option that doesn't exist in Home-Manager.

**Solution:** Check if the tool has a Home-Manager module:
```bash
# Search for module
nix-shell -p home-manager --run "home-manager search <tool>"

# If no module exists, use home.file or programs.<tool>.extraConfig
```

### Changes Not Taking Effect After Rebuild

**Problem:** Modified `users/martin/home.nix`, rebuilt, but change didn't apply.

**Cause:** Home-Manager requires explicit activation.

**Solution:**
```bash
# Make sure device config imports the user home-manager setup:
# In hosts/device/default.nix:
home-manager.users.martin = {
  imports = [ "${self}/users/martin/home.nix" ];
};

# Then rebuild
nixos-rebuild switch
```

### Dotfile Permissions Wrong

**Problem:** Home-Manager created file with wrong permissions (e.g., not executable).

**Solution:**
```nix
home.file.".config/script.sh" = {
  source = ./script.sh;
  executable = true;
};
```

### State Directory Not Created

**Problem:** Home-Manager module expects `.config/app/` directory but it doesn't exist.

**Solution:** Home-Manager doesn't auto-create parent directories:
```nix
home.file.".config/app/state".text = "";  # Create directory
# OR
systemd.user.tmpfiles.rules = [
  "d ~/.config/app 0755"
];
```

---

## Advanced Patterns

### Conditional Configuration (Device-Specific)

```nix
# In users/martin/home.nix
{ config, ... }:
let
  isWorkstation = config.my.desktop.enable or false;
in
{
  modules.gnome.enable = isWorkstation;
  modules.dev.enable = isWorkstation;
  modules.vscode.enable = isWorkstation;
}
```

### User-Specific Secrets

```nix
# In hosts/device/secrets.nix
sops.secrets."users/martin/github_token" = {
  owner = "martin";
  path = "/run/secrets/martin_github_token";
};

# In users/martin/home.nix
programs.gh.settings.git_protocol = "ssh";
home.sessionVariables.GITHUB_TOKEN = 
  "$(cat /run/secrets/martin_github_token)";
```

### Multiple Home Profiles

```nix
# users/martin/home-phone.nix — minimal mobile config
# users/martin/home.nix — full workstation config
# Switch at activation based on device type
```

### Shared Module for Multiple Users

```nix
# modules/home-manager/shared-dev.nix
{ ... }:
{
  imports = [
    ./dev.nix        # Git, npm, etc.
    ./security.nix   # SSH, age, sops
  ];
}

# Then in users/alice/home.nix
imports = [ "${self}/modules/home-manager/shared-dev.nix" ];
```

---

## Migration & Updates

### Updating Home-Manager State Version

When NixOS version changes (e.g., 25.05 → 25.11):

```nix
# In users/martin/home.nix
home.stateVersion = "25.11";  # Update this

# Then rebuild
nixos-rebuild switch
```

### Backing Up User Configuration

```bash
# Export home-manager generation
home-manager expire-generations "3 days"

# Or manually backup
tar czf ~/martin-home-backup.tar.gz ~/.config ~/.local
```

### Cleaning Up Old Generations

```bash
# Remove old Home-Manager generations (keeps last 3)
nix-collect-garbage --delete-old

# Show generations
home-manager generations
```

---

## Common Use Cases

### Setup New Workstation (nixos-nvme style)

```nix
# users/newdev/home.nix
{
  imports = [
    "${self}/modules/home-manager/default.nix"
  ];
  
  modules = {
    dev.enable = true;
    gnome.enable = true;
    vscode.enable = true;
    nixvim.enable = true;
    security.enable = true;
    workspace-guardian.enable = true;
  };
  
  home.username = "newdev";
  home.homeDirectory = "/home/newdev";
  home.stateVersion = "25.11";
  
  # Custom packages
  home.packages = [ ... ];
}
```

### Setup Headless User (build/automation)

```nix
# users/builder/home.nix
{
  imports = [ "${self}/modules/home-manager/default.nix" ];
  
  modules = {
    dev.enable = true;    # Git, basic tools
    security.enable = true; # SSH, sops
  };
  
  home.username = "builder";
  home.homeDirectory = "/home/builder";
  home.stateVersion = "25.11";
}
```

### Setup Restricted User (limited tools)

```nix
# users/guest/home.nix
{
  home.username = "guest";
  home.homeDirectory = "/home/guest";
  home.stateVersion = "25.11";
  
  # Minimal setup, no dev tools, no system access
  home.packages = with pkgs; [
    firefox     # Browser only
    xdg-utils   # Desktop integration
  ];
}
```

---

## Integration with Rest of Fleet

### Deploying User Config to Remote Device

```bash
# After modifying users/martin/home.nix:
nixos-rebuild switch -h 10.0.0.15  # Deploy to orin-nano

# Home-Manager activates automatically at next login
```

### Sharing Config Across Devices

Users configured on multiple devices (e.g., martin on nixos-nvme and mac-mini):

```nix
# hosts/nixos-nvme/default.nix
home-manager.users.martin = {
  imports = [ "${self}/users/martin/home.nix" ];
};

# hosts/mac-mini/default.nix (identical)
home-manager.users.martin = {
  imports = [ "${self}/users/martin/home.nix" ];
};
```

---

## Related Documentation

- **DEVICE-TIERS.md** — Device-level configuration
- **DEPLOYMENT-STRATEGY.md** — Safe changes
- **SECRETS-MANAGEMENT.md** — Secrets integration
- **TROUBLESHOOTING.md** — Common issues

---

## Further Reading

- [Home-Manager Manual](https://nix-community.github.io/home-manager/)
- [Available Modules](https://nix-community.github.io/home-manager/options.html)
- [NixOS Manual - Home-Manager](https://nixos.org/manual/nixos/stable/index.html#sec-declarative-package-mgmt)

---

**Last Updated:** 2026-08-18  
**Status:** Complete user environment configuration guide  
**Audience:** New users, developers, maintainers
