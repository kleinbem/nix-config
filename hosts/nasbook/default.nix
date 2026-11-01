# nasbook — QNAP TBS-453A
{
  lib,
  inputs,
  self,
  myInventory,
  config,
  secretFile,
  ...
}:
let
  keys = import "${self}/modules/nixos/keys.nix";
in
{
  imports = [
    # Disk setup via disko (replaces legacy hardware-configuration.nix, see ./disko.nix)
    inputs.disko.nixosModules.disko
    ./disko.nix
    "${self}/modules/nixos/data-disk.nix"
    ./data-disk.nix
    "${self}/modules/nixos/base.nix" # foundational, imported by every entry-point bundle
    "${self}/modules/nixos/headless.nix"
    "${self}/modules/nixos/hosts.nix"
    "${self}/modules/nixos/clevis-initrd.nix"
    # Root is stateless tmpfs (disko.nix) — this binds /var/lib/* service
    # state back from the persistent /nix/persist btrfs subvolume.
    "${self}/modules/nixos/persistence.nix"
    "${self}/modules/nixos/pull-deploy-node.nix"
    # ADR-002: containers below are decoupled/pulled, not built on this weak
    # host (see container-factory's catalogue for their pre-built closures).
    inputs.nix-gantry.nixosModules.host
    inputs.nix-gantry.nixosModules.host-persistence
    inputs.nix-gantry.nixosModules.updater

    # ─── Services moved from Workstation ─────────────────────
    inputs.nix-presets.nixosModules.paperless
    inputs.nix-presets.nixosModules.agent-team
    inputs.nix-presets.nixosModules.monitoring
    inputs.nix-presets.nixosModules.loki
    inputs.nix-presets.nixosModules.syncthing
    inputs.nix-presets.nixosModules.qdrant
    inputs.nix-presets.nixosModules.backup
    inputs.nix-presets.nixosModules.monitoring-node
    inputs.nix-presets.nixosModules.herdr-remote-client
    inputs.nix-presets.nixosModules.qbittorrent
    inputs.nix-presets.nixosModules.miniflux

    # Needs SOPS to unlock the secrets below
    ./secrets.nix
  ];

  # headless.nix only creates the user; each host authorizes its own keys.
  users.users.martin.openssh.authorizedKeys.keys = [
    keys.ssh.yubikey
    keys.ssh.fido2
    keys.ssh.fido2-backup
  ];

  my = {
    # External dead-man's switch (modules/nixos/heartbeat.nix): <host>-alive
    # every 5 min + a ping per backup job; missing pings alert from
    # healthchecks.io, outside the fleet. Always-on hosts only.
    heartbeat.enable = true;
    # Tang auto-unlock; disko.nix's fido2-device=auto is the HDMI/TTY fallback.
    # Binds only to other hosts' tang servers: nasbook can't serve itself
    # before it's unlocked. Gated on the JWE made at provisioning.
    boot.clevis-initrd = {
      enable = builtins.pathExists (secretFile "initrd/cryptroot_nasbook.jwe");
      luksDevice = "nasbook_crypt";
      hostIp = "10.0.0.30"; # inventory.nix — excludes nasbook's own tang server from the wait loop
      secretFile = secretFile "initrd/cryptroot_nasbook.jwe";
      fallbackMessage = "Tang still unreachable; falling back to the recovery passphrase over initrd SSH or the HDMI/TTY console.";
    };

    herdr-remote-client = {
      enable = true;
      serverIp = "10.0.0.5"; # nixos-nvme physical LAN IP (inventory.nix)
    };

    # Backups — nix-presets' backup-engine, fleet wiring in
    # modules/nixos/backup.nix. tang, paperless-db, and qbittorrent register
    # their own items. nasbook registers syncthing (identity/keys), agent-team,
    # and paperless intake inbox plus exclude rules for search index/logs.
    # Secrets: backup_r2_rclone_config (nix/per-host/nasbook.yaml),
    # rclone_config/restic_password/ntfy_alert_topic (nix/shared.yaml).
    backup = {
      enable = true;
      items = {
        syncthing = {
          tier = "secure";
          paths = [ "/var/lib/images/syncthing" ];
          exclude = [ "/var/lib/images/syncthing/syncthing.lock" ];
        };
        agent-team = {
          tier = "secure";
          paths = [ "/var/lib/images/agent-team" ];
        };
        paperless-documents = {
          paths = [ "/mnt/data/Archive/Inbox" ];
          exclude = [
            "/mnt/data/Archive/Paperless/index"
            "/mnt/data/Archive/Paperless/log"
            "/mnt/data/Archive/Paperless/celerybeat-schedule.db*"
          ];
        };
      };
    };

    # comin follows the production branch, signed heads only. requireCache:
    # this host never compiles; CI builds its toplevel before promote.
    deploy = {
      autoUpgrade.enable = false;
      comin = {
        enable = true;
        requireCache = true;
      };
    };

    # enp4s0 (Realtek, r8169) is the cabled port; enp3s0 (Intel I210) is unused.
    network.externalInterface = "enp4s0";

    # my.virtualisation.enable gates podman-network-cbr0, which creates the
    # cbr0 bridge every container attaches to; podman.enable alone is inert.
    virtualisation = {
      enable = true;
      libvirtd.enable = false;
      podman.enable = true;
    };

    # ─── Container Hosting (via reusable module) ─────────────
    # Supplies my.network.subnet/.hostAddress (externalInterface stays
    # above — container-host.nix doesn't set it) plus the container-updater
    # auto-derivation and persistence wiring every other container-hosting
    # node already uses (core-pi, mac-mini, hass-pi).
    container-host = {
      enable = true;
      subnet = "10.85.47.0/24";
      hostAddress = "10.85.47.1";
      manifestUrl = "https://github.com/kleinbem/nix-config/releases/download/container-manifest/manifest.json";
      # nix-gantry defaults this off (it needs impermanence); this fleet has it.
      enablePersistence = true;
    };

    # ─── Data & Analytics Hub Services ───────────────────────
    containers = {
      paperless = {
        enable = true;
        ip = "${myInventory.network.nodes.paperless.ip}/24";
        hostDataDir = "/mnt/data/Archive/Paperless";
        hostConsumptionDir = "/mnt/data/Archive/Inbox";
        passwordFile = config.sops.secrets.paperless_password.path;
      };

      agent-team = {
        enable = true;
        ip = "${myInventory.network.nodes.agent-team.ip}/24";
      };

      monitoring = {
        enable = false;
        ip = "${myInventory.network.nodes.monitoring.ip}/24";
        hostDataDir = "/var/lib/images/monitoring";
        # Automatically scrape the host and important infrastructure nodes
        nodeTargets = [
          myInventory.hosts.nixos-nvme.ip
          myInventory.hosts.core-gateway.ip
          myInventory.hosts.ap-upstairs.ip
        ];
      };

      loki = {
        enable = true;
        ip = "${myInventory.network.nodes.loki.ip}/24";
        hostDataDir = "/var/lib/images/loki";
      };

      qdrant = {
        # Upstream nixos-unstable rustc/LLVM stdarch drift (rust-lang/rust#111137).
        # Kept active via the fleet's transparent nixpkgs-stable circuit-breaker fallback.
        enable = true;
        ip = "${myInventory.network.nodes.qdrant.ip}/24";
        hostDataDir = "/var/lib/images/qdrant";
        memoryLimit = "2G";
      };

      syncthing = {
        enable = true;
        ip = "${myInventory.network.nodes.syncthing.ip}/24";
        hostDataDir = "/var/lib/images/syncthing";
      };

      qbittorrent = {
        enable = true;
        ip = "${myInventory.network.nodes.qbittorrent.ip}/24";
        hostDataDir = "/var/lib/images/qbittorrent";
        downloadsDir = "/mnt/data/Downloads";
      };

      miniflux = {
        enable = true;
        ip = "${myInventory.network.nodes.miniflux.ip}/24";
        hostDataDir = "/var/lib/images/miniflux";
      };
    };
    monitoring.node.enable = true;
  };

  systemd = {
    # IMAGE STATE STORAGE
    tmpfiles.rules = [
      "d /var/lib/images 0755 root root - -"
      "d /var/lib/images/loki 0755 root root - -"
      "d /var/lib/images/monitoring 0755 root root - -"
      "d /var/lib/images/qdrant 0755 root root - -"
      "d /var/lib/images/syncthing 0755 root root - -"
      "d /var/lib/images/miniflux 0755 root root - -"
      "d /mnt/data/Archive 0755 martin users - -"
      "d /mnt/data/Archive/Inbox 0755 martin users - -"
      "d /mnt/data/Archive/Paperless 0755 root root - -"
      # agent-team's bind-mount sources; the container won't start without them.
      "d /var/lib/images/agent-team 0755 root root - -"
      "d /var/lib/images/agent-team/workspace 0755 root root - -"
      "d /var/lib/images/agent-team/state 0755 root root - -"
    ];
  };

  # ─── Networking & Security ──────────────────────────────────
  services = {
    netbird.enable = true;
    fstrim.enable = true;

    # dhcpcd points resolv.conf at the resolved stub, so resolved must run, or
    # DNS (and with it NTP) fails.
    resolved.enable = true;
  };

  # paperless trusts the X-Authentik-Username header for SSO, and its port is
  # routable fleet-wide, so a spoofed header would log anyone in. Only Caddy
  # may reach it. core-pi masquerades all cbr0 egress, so Caddy arrives as
  # core-pi's LAN IP. 10.85.47.1 is this host's bridge, for local admin.
  networking = {
    hostName = "nasbook";

    nftables.enable = true;

    firewall = {
      enable = true;
      backend = "nftables";
      filterForward = true;
      interfaces."wt0".allowedTCPPorts = [ 22 ];
      extraForwardRules = lib.mkBefore ''
        ip daddr ${myInventory.network.nodes.paperless.ip} tcp dport ${toString myInventory.network.nodes.paperless.port} ip saddr { ${myInventory.hosts.core-pi.ip}, 10.85.47.1 } accept
        ip daddr ${myInventory.network.nodes.paperless.ip} tcp dport ${toString myInventory.network.nodes.paperless.port} drop
      '';
    };
  };

  boot.loader = {
    systemd-boot.enable = true;
    efi.canTouchEfiVariables = true;
  };

  boot.initrd = {
    # The default initrd has no Ethernet drivers, so Tang would silently fall
    # back to FIDO2/passphrase. Both onboard NICs, in case the cable moves.
    kernelModules = [
      "r8169"
      "igb"
    ];

    # Remote unlock fallback, same pattern as nixos-nvme/mac-mini — lets us
    # unlock over SSH instead of needing physical HDMI/keyboard access.
    network.ssh = {
      enable = true;
      port = 2222;
      authorizedKeys = [
        keys.ssh.yubikey
        keys.ssh.fido2
        keys.ssh.fido2-backup
      ];
      hostKeys = [ "/etc/ssh/ssh_host_ed25519_key_nasbook" ];
    };
    secrets."/etc/ssh/ssh_host_ed25519_key_nasbook" = lib.mkForce config.my.hostSecrets.initrdSshKey;
  };

  system.stateVersion = "25.11"; # Or whatever the current state version is
  my.services.tang.enable = true;
}
