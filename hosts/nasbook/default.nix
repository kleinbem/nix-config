# nasbook — QNAP TBS-453A
{
  lib,
  inputs,
  self,
  myInventory,
  config,
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
    # ADR-002: containers below are decoupled/pulled, not built on this weak
    # host (see container-factory's catalogue for their pre-built closures).
    "${self}/modules/nixos/container-host.nix"
    "${self}/modules/nixos/services/container-updater.nix"

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

    # Needs SOPS to unlock the secrets below
    ./secrets.nix
  ];

  # headless.nix creates the martin user but — unlike orin-nano/core-pi/
  # hass-pi — nothing here ever authorized a key for it, so it was actually
  # unreachable by SSH. Same fleet-wide key set as everywhere else.
  users.users.martin.openssh.authorizedKeys.keys = [
    keys.ssh.yubikey
    keys.ssh.fido2
    keys.ssh.fido2-backup
  ];

  my = {
    # Tang auto-unlock at boot, same pattern as hass-pi/mac-mini/core-pi —
    # silent primary path; disko.nix's fido2-device=auto crypttab option is
    # the physical-presence fallback (HDMI+TTY per .just/nasbook.just) if
    # Tang is unreachable. Binds to the OTHER three tang servers (nixos-nvme,
    # hass-pi, orin-nano — see pc_clevis_bind_tang), never to nasbook's own
    # (it can't serve itself an advertisement before it's unlocked). `enable`
    # is gated on the JWE existing rather than hardcoded true: nasbook-install-usb
    # generates it during provisioning, same as every other clevis-initrd host.
    boot.clevis-initrd = {
      enable = builtins.pathExists (inputs.kleinbem-secrets + "/initrd/cryptroot_nasbook.jwe");
      luksDevice = "nasbook_crypt";
      hostIp = "10.0.0.30"; # inventory.nix — excludes nasbook's own tang server from the wait loop
      secretFile = inputs.kleinbem-secrets + "/initrd/cryptroot_nasbook.jwe";
      fallbackMessage = "Tang still unreachable; falling back to the recovery passphrase over initrd SSH or the HDMI/TTY console.";
    };

    herdr-remote-client = {
      enable = true;
      serverIp = "10.0.0.5"; # nixos-nvme physical LAN IP (inventory.nix)
    };

    # Pull-deploy; substitute-only — this laptop is too weak for long builds.
    # Gate the nightly run on cache reachability and cap its runtime.
    deploy.autoUpgrade = {
      enable = true;
      requireCache = true;
      # core-pi/hass-pi get this transitively via rpi5-node.nix; nasbook isn't
      # that hardware so it doesn't import it, but it should still get the
      # same instant-on-promote fast path rather than only the 04:00 timer.
      ntfy.enable = true;
    };

    # Confirmed via lspci on the real hardware 2026-09-17: enp4s0 is the
    # connected port (Realtek RTL8111/8168, r8169). enp3s0 (Intel I210,
    # igb) is the second onboard NIC, currently uncabled. "enp2s0" here
    # before was copied from another host and never matched real hardware.
    network.externalInterface = "enp4s0";

    # my.virtualisation.enable gates podman-network-cbr0, the service that
    # actually creates the shared cbr0 bridge every container — podman or
    # nspawn — attaches to. podman.enable defaults to true on its own, but
    # that default is inert without this. Identical to the mac-mini bug
    # fixed 2026-08-04 ("Failed to add interface vb-monitoring to bridge
    # cbr0: No such device" — cbr0 never created because this host never
    # ran a container before); rpi5-node.nix sets this automatically for
    # core-pi/hass-pi, but nasbook (non-Pi hardware) needs it explicitly
    # and never got it.
    virtualisation = {
      enable = true;
      libvirtd.enable = false;
      podman.enable = true;
      lxc.enable = false;
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
        # Disabled fleet-wide-broken, not nasbook-specific: nixpkgs' current
        # rustc/LLVM pin fails to build qdrant's `quantization` crate with
        # "intrinsic signature mismatch for llvm.x86.avx512.vpdpbusd.512" —
        # an upstream stdarch/LLVM drift (rust-lang/rust#111137), not a
        # config issue. Re-enable once nixpkgs bumps past the fix.
        enable = false;
        ip = "${myInventory.network.nodes.qdrant.ip}/24";
        hostDataDir = "/var/lib/images/qdrant";
        memoryLimit = "2G";
      };

      syncthing = {
        enable = true;
        ip = "10.85.47.127/24";
        hostDataDir = "/var/lib/images/syncthing";
      };

      backup = {
        enable = true;
        ip = "${myInventory.network.nodes.backup.ip}/24";
        passwordFile = config.sops.secrets.restic_password.path;
        systemPasswordFile = config.sops.secrets.restic_system_password.path;
        rcloneConfigFile = config.sops.secrets.rclone_config.path;
        targets = {
          "/mnt/data" = "/mnt/data";
        };
        systemTargets = {
          "/var/lib/images" = "/var/lib/images";
        };
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
      "d /mnt/data/Archive 0755 martin users - -"
      "d /mnt/data/Archive/Inbox 0755 martin users - -"
      "d /mnt/data/Archive/Paperless 0755 root root - -"
      # agent-team's bind-mount sources (nix-presets/containers/agent-team.nix
      # defaults hostDataDir to /var/lib/images/agent-team) — was missing
      # entirely, same class of gap as GoogleDrive above: "Failed to clone
      # /var/lib/images/agent-team/state: No such file or directory".
      "d /var/lib/images/agent-team 0755 root root - -"
      "d /var/lib/images/agent-team/workspace 0755 root root - -"
      "d /var/lib/images/agent-team/state 0755 root root - -"
    ];
  };

  # ─── Networking & Security ──────────────────────────────────
  services = {
    netbird.enable = true;
    fstrim.enable = true;

    # dhcpcd already writes /etc/resolv.conf pointing at the resolved stub
    # (127.0.0.1) on this NixOS version, but resolved itself was never
    # enabled — so nothing was listening and every DNS lookup failed
    # ("Could not resolve host"), which in turn kept systemd-timesyncd from
    # resolving its NTP pool (root cause of the boot clock reading 2012).
    resolved.enable = true;
  };

  # paperless trusts an unauthenticated Remote-User header for SSO login
  # (PAPERLESS_ENABLE_HTTP_REMOTE_USER, nix-presets/containers/paperless.nix)
  # — normally safe because only Caddy's forward_auth (after a verified
  # Authelia session) is meant to set that header. But paperless's own
  # container port is otherwise reachable by anyone who can route to
  # nasbook's cbr0, including cross-host (network-routing.nix installs a
  # route to every host's container subnet on every other host), which
  # bypasses Caddy/Authelia entirely. Confirmed exploitable live
  # 2026-09-19: curling http://10.85.47.131:28981/ directly with
  # `-H "Remote-User: admin"` logs straight into the dashboard with no
  # credentials, while the same request without the header correctly
  # redirects to /accounts/login/.
  #
  # NOT fixed via networking.firewall.extraForwardRules — that option only
  # exists on the nftables firewall backend (nixpkgs'
  # firewall-nftables.nix); nasbook uses the classic iptables backend
  # (networking.firewall.backend == "iptables", confirmed live 2026-09-19),
  # where extraForwardRules is silently inert — container-host.nix's own
  # nftables-syntax "extraForwardRules" have in fact never done anything on
  # this host. The iptables backend's forward-chain filtering instead comes
  # from networking.nat (nat-iptables.nix's "nixos-filter-forward" chain:
  # unconditional cbr0->WAN accept + established/related accept, then falls
  # through to the kernel's default FORWARD policy, which is ACCEPT — so
  # nothing was blocking this at all). networking.nat.extraCommands is the
  # correct injection point for that backend: it's appended into
  # nixos-filter-forward, after the existing accepts but before that
  # fallthrough. Verified via a live tcpdump that cross-host container
  # traffic isn't NAT'd here (no source-IP masquerade on this path), so
  # matching Caddy's real container IP as the source is reliable — same
  # convention zero-trust.nix already uses for same-host flows.
  # 10.85.47.1 is nasbook's own bridge address, allowed for host-side
  # debugging/administration.
  networking = {
    hostName = "nasbook";

    firewall = {
      enable = true;
      interfaces."wt0".allowedTCPPorts = [ 22 ];
    };

    nat.extraCommands = ''
      iptables -w -t filter -A nixos-filter-forward -d ${myInventory.network.nodes.paperless.ip} -p tcp --dport ${toString myInventory.network.nodes.paperless.port} -s ${myInventory.network.nodes.caddy.ip} -j ACCEPT
      iptables -w -t filter -A nixos-filter-forward -d ${myInventory.network.nodes.paperless.ip} -p tcp --dport ${toString myInventory.network.nodes.paperless.port} -s 10.85.47.1 -j ACCEPT
      iptables -w -t filter -A nixos-filter-forward -d ${myInventory.network.nodes.paperless.ip} -p tcp --dport ${toString myInventory.network.nodes.paperless.port} -j DROP
    '';
  };

  boot.loader = {
    systemd-boot.enable = true;
    efi.canTouchEfiVariables = true;
  };

  boot.initrd = {
    # QNAP TBS-453A onboard NIC — never explicitly loaded (no hardware.nix
    # survived the hardware-configuration.nix→disko migration, and NixOS's
    # default initrd module set is storage/HID only, no Ethernet drivers).
    # Without this, systemd-networkd has no interface to bring up in stage 1,
    # so wait-for-tang.service's carrier check always times out and Tang
    # auto-unlock silently falls back to FIDO2/passphrase on every boot.
    # Confirmed via lspci 2026-09-17: enp4s0 (the connected port) is a
    # Realtek RTL8111/8168 on r8169; enp3s0 (uncabled) is an Intel I210 on
    # igb. Both loaded here so Tang still works in initrd if the cable
    # ever moves to the other port.
    kernelModules = [
      "r8169"
      "igb"
    ];

    # Remote unlock fallback, same pattern as nixos-nvme/mac-mini — lets us
    # unlock over SSH instead of needing physical HDMI/keyboard access.
    network.ssh = {
      enable = builtins.pathExists (inputs.kleinbem-secrets + "/initrd/ssh_host_ed25519_key_nasbook");
      port = 2222;
      authorizedKeys = [
        keys.ssh.yubikey
        keys.ssh.fido2
        keys.ssh.fido2-backup
      ];
      hostKeys = [ "/etc/ssh/ssh_host_ed25519_key_nasbook" ];
    };
    secrets."/etc/ssh/ssh_host_ed25519_key_nasbook" = lib.mkForce (
      inputs.kleinbem-secrets + "/initrd/ssh_host_ed25519_key_nasbook"
    );
  };

  system.stateVersion = "25.11"; # Or whatever the current state version is
  my.services.tang.enable = true;
}
