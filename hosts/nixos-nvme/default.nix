{
  pkgs,
  lib,
  config,
  inputs,
  self,
  options,
  ...
}:

{
  imports = [
    inputs.nix-hardware.nixosModules.nixos-nvme
    inputs.nix-hardware.nixosModules.intel-compute
    "${self}/modules/nixos/workstation.nix"
    "${self}/modules/nixos/hosts.nix"
    "${self}/modules/nixos/default.nix"
    "${self}/users/martin/nixos.nix"
    "${self}/users/dhirujaan/nixos.nix"

    # Whole preset catalogue (Switchboard: everything defaults off; the
    # my.* enables below and in containers.nix/ai.nix pick what runs).
    # Edge hosts keep selective imports — they eval their own config nightly.
    inputs.nix-presets.nixosModules.all

    "${self}/modules/nixos/persistence.nix"
    ./secrets.nix
    "${self}/modules/nixos/apps.nix"
    "${self}/modules/nixos/disko.nix"
    "${self}/modules/nixos/data-disk.nix"
    inputs.disko.nixosModules.disko
    ./ai.nix
    "${self}/modules/nixos/containers/langgraph.nix"
    inputs.nix-gantry.nixosModules.updater

    ./hardware-boot.nix
    ./network.nix
    ./containers.nix
    ./garage.nix
    "${self}/modules/nixos/services/vault-anythingllm-sync.nix"
    ./monitors.nix
    ./herdr.nix
  ];

  # Lets other fleet devices (orin-nano, phone) SSH in, e.g. to attach a remote
  # herdr client. Same keys as the initrd unlock sshd (hardware-boot.nix).
  users.users.martin.openssh.authorizedKeys.keys =
    with (import "${self}/modules/nixos/keys.nix").ssh; [
      yubikey
      fido2
      fido2-backup
      tablet-termux
      phone-termux
    ];

  # nixpkgs PR work happens on this host: substitute what nixpkgs-review-gha
  # already built for the open PRs instead of rebuilding it locally.
  nix.settings = {
    substituters = [ "https://kleinbem-nixpkgs-review.cachix.org" ];
    trusted-public-keys = [
      (import "${self}/modules/nixos/keys.nix").cachix.kleinbem-nixpkgs-review
    ];
  };

  environment = {
    etc = { };
    variables = { };
    systemPackages = with pkgs; [
      sops
      age
      age-plugin-yubikey
      age-plugin-tpm
      libfido2
      pam_u2f
      sbctl
      niv
      cups # Client tools (lpstat, etc.)
      yubikey-personalization
      openssl
      parted
      dosfstools
      tio # serial terminal (USB-TTL, embedded devices)
      efibootmgr # EFI NVRAM entry management (recovery + boot guard)
      bind.dnsutils # provides nslookup, dig
      google-antigravity # Google Antigravity 2.0 (orchestration hub) -> binary: antigravity
      google-antigravity-ide-no-fhs # Google Antigravity IDE -> binary: antigravity-ide
      google-antigravity-cli # Google Antigravity CLI -> binary: antigravity-cli, agy
      google-chrome # Google Chrome browser (provides system-wide chrome binary)
      buzz-cli # Agent-first CLI for the Buzz relay and workspace (binary: buzz)
      buzz-acp # Agent Control Protocol (ACP) bridge for autonomous agents
      git-credential-nostr # NIP-98 credential helper for Nostr git repositories
      git-sign-nostr # NIP-GS commit/tag signing program using Nostr secp256k1 keys
      buzz-dev-mcp # Model Context Protocol (MCP) server for Buzz developers and AI coding agents
      buzz-agent # Minimal, unbreakable ACP-compliant autonomous AI agent for Buzz workspace
      buzz-app # Buzz 1.0 desktop app (NixOS/nixpkgs#577918 via nix-packages' nixpkgs-prs pin)
      berd # Berd desktop app for Goose agents (NixOS/nixpkgs#580616 via nix-packages' nixpkgs-prs pin)

      # RDP clients for mac-mini (`ssh -L 3389:localhost:3389 mac-mini`).
      # GNOME Connections hides errors; freerdp prints them, remmina is the GUI.
      freerdp
      remmina
    ];
  };

  security.pki.certificateFiles = [
    ../../pki/caddy-root.crt
  ];

  my = {
    security.ai-hardening.enable = true;
    monitoring.node.enable = true;
    services = {
      snapper.enable = true;
      tang.enable = true;
      threeDPrinting.enable = true; # Bambu Lab A1 mini: slicers + LAN discovery
    };
    # Fleet backups (modules/nixos/backup.nix); tang, buzz, caido and dev-db
    # register their own items. /home and per-app state still go through the
    # legacy backup container (containers.nix).
    backup.enable = true;
    dataDisk = {
      enable = true;
      device = "/dev/disk/by-id/ata-WD_Red_SA500_2.5_2TB_2548TKD00121";
    };
    deploy.autoUpgrade = {
      enable = true;
      # CI builds this toplevel (build-nvme.yaml), so a cache miss should
      # abort and retry next cycle rather than compile the closure locally.
      requireCache = true;
    };
    # Claude Code's permission and auto-mode policy, as read-only managed
    # settings (modules/nixos/claude-code.nix).
    claudeCode.enable = true;
    desktop = {
      gnome.enable = true;
      claude.enable = true;
      # Windows apps via Bottles (ntsync, 32-bit graphics; no gaming tweaks)
      bottles.enable = true;
      # Discord/Element/Signal in nixpak sandboxes (replacing firejail.nix)
      sandboxedApps.enable = true;
    };
    audio.jabra.preferred = true;
    virtualisation = {
      enable = true;
      libvirtd.enable = true; # workstation needs virt-manager + KVM
    };
    android.enable = true;
  };

  services = {
    # SystemMaxUse restates core.nix's 4G (mkForce resolves the attrset merge
    # in the settings branch); the other keys are host-only. See core.nix for
    # why both branches exist.
    journald =
      if options.services.journald ? settings then
        {
          settings.Journal = {
            SystemMaxUse = lib.mkForce "4G";
            SystemMaxFileSize = "128M";
            MaxRetentionSec = "1month";
          };
        }
      else
        {
          extraConfig = ''
            SystemMaxUse=4G
            SystemMaxFileSize=128M
            MaxRetentionSec=1month
          '';
        };
    pcscd.enable = true;
    fprintd.enable = true;
  };

  # ── Memory-creep logger ───────────────────────────────────────────
  # Past freezes were slow anonymous-memory creep, and journald dies once the
  # host thrashes, hiding the culprit. Log the top swap/RSS users every 10 min
  # (tag `mem-creep`). Retire once the leak is found.
  systemd.services.mem-creep-logger = {
    description = "Log top memory/swap consumers for leak diagnosis";
    serviceConfig = {
      Type = "oneshot";
      Nice = 19;
      IOSchedulingClass = "idle";
      SyslogIdentifier = "mem-creep";
    };
    path = [
      pkgs.gawk
      pkgs.gnugrep
      pkgs.coreutils
    ];
    script = ''
      grep -E 'MemTotal|MemAvailable|SwapTotal|SwapFree' /proc/meminfo \
        | tr '\n' ' '
      echo
      # Per-process VmSwap + VmRSS from /proc/<pid>/status, top 15 by swap.
      gawk '
        FNR == 1 { name = ""; rss = 0; swap = 0 }
        /^Name:/   { name = $2 }
        /^VmRSS:/  { rss  = $2 }
        /^VmSwap:/ { swap = $2 }
        ENDFILE {
          if (swap > 0) {
            pid = FILENAME; gsub(/[^0-9]/, "", pid)
            printf "%9d KiB swap  %9d KiB rss  %-20s (pid %s)\n", swap, rss, name, pid
          }
        }
      ' /proc/[0-9]*/status 2>/dev/null | sort -rn | head -15
    '';
  };
  systemd.timers.mem-creep-logger = {
    description = "Sample top memory/swap consumers every 10 minutes";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "5min";
      OnUnitActiveSec = "10min";
      AccuracySec = "1min";
    };
  };

  # Over core.nix's 50%: the workstation parks many idle Chrome tabs and AI
  # workloads in zram, and zstd's ~2-3x ratio makes 100% cheap in real RAM.
  zramSwap.memoryPercent = lib.mkForce 100;

  home-manager.users.${config.my.username} = {
    imports = [
      "${self}/users/martin/home.nix"
      # Physical-hardware quirk specific to this desktop's YubiKey — see the
      # file for why it lives here rather than in the shared home.nix.
      ./ssh-fido-recovery.nix
      # Pulls Caddy's internal root CA over SSH from core-pi (the only host
      # that runs it) — host-specific because it hardcodes that relationship.
      ./caddy-ca-refresh.nix
      # Keeps the Obsidian vault self-maintaining (organize/distill-flag/
      # link-docs) instead of relying on manual `just os notes::*` runs.
      ./notes-maintenance.nix
    ];
  };
  home-manager.users.dhirujaan = import "${self}/users/dhirujaan/home.nix";

  # NOTE: the efi-boot-guard service lives in ./hardware-boot.nix (it also
  # enforces BootOrder). Don't redefine it here — systemd.services.<n>.script
  # is types.lines, so a second definition silently concatenates rather than
  # erroring, duplicating the restore/NVRAM logic.

  # Short boot menu label (systemd-boot truncates long generation names).
  system.nixos.label = lib.trivial.release;
  system.stateVersion = "25.11";

}
