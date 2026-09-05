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
    ./specialisations.nix
    "${self}/modules/nixos/services/container-updater.nix"

    ./hardware-boot.nix
    ./network.nix
    ./containers.nix
    ./garage.nix
  ];

  # security/ssh.nix (workstation tier) requires publickey+MFA but this host
  # never actually authorized a key for its own normal sshd (port 22) — only
  # the initrd-stage unlock sshd (hardware-boot.nix, port 2222) had one, with
  # the same key set. Needed so other fleet devices (orin-nano, phone) can
  # SSH in, e.g. to attach a remote herdr client to the server running here.
  users.users.martin.openssh.authorizedKeys.keys =
    with (import "${self}/modules/nixos/keys.nix").ssh; [
      yubikey
      fido2
      fido2-backup
    ];

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
      google-antigravity-ide-no-fhs # Google Antigravity IDE
      buzz-desktop # Client for the self-hosted Buzz relay (containers.nix)

      # RDP clients for mac-mini's GNOME Remote Desktop (reached via
      # `ssh -L 3389:localhost:3389 mac-mini`, see hosts/mac-mini/default.nix).
      # GNOME Connections (already installed via desktop.nix's core-apps)
      # gave a confusing "not responding" error on a credential-provisioning
      # race — freerdp gives a CLI fallback (wlfreerdp, native Wayland) with
      # actual error output instead of a silent GUI hang; remmina is a more
      # full-featured GUI alternative.
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
    services.tang.enable = true;
    deploy.autoUpgrade.enable = true;
    services.threeDPrinting.enable = true; # Bambu Lab A1 mini: slicers + LAN discovery
    desktop = {
      gnome.enable = true;
      claude.enable = true;
    };
    audio.jabra.preferred = true;
    virtualisation = {
      enable = true;
      libvirtd.enable = true; # workstation needs virt-manager + KVM
    };
    android.enable = true;
  };

  services = {
    # 4G, matching core.nix: 500M rotated out in hours on this host (runner +
    # fluent-bit churn), which made the 2026-07-15 freeze un-diagnosable.
    # SystemMaxUse restates core.nix's own value (mkForce in the settings
    # branch, to resolve the attrset merge conflict); the other two keys
    # aren't set there. See core.nix for why both branches exist.
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
  # The 2026-07-15 and 2026-07-22 freezes were both slow anonymous-memory
  # creep filling swap over days. journald backlogs and dies once thrashing
  # starts, so the offender is invisible after the fact. This samples the top
  # swap/RSS consumers every 10 min at idle priority and logs them to the
  # journal (tag `mem-creep`), so the next creep is attributable to a process.
  # Retire once the leaker is identified and fixed.
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

  # Shorten the boot menu label so specialisation names are visible in systemd-boot.
  system.nixos.label = lib.trivial.release;
  system.stateVersion = "25.11";

}
