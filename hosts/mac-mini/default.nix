# mac-mini — Mid-2011 Mac Mini (Macmini5,x), Intel, real 64-bit EFI.
#
# Role: dedicated interactive box (no physical keyboard/mouse/screen — GUI
# access is remote-desktop only). First concrete use case: join/record Zoom
# calls from a container. Provisioned like orin-nano/core-pi/hass-pi — SSD
# wiped+installed via USB-SATA adapter (see .just/deployment.just
# mac-mini-install-usb), then moved internally.
{
  config,
  lib,
  pkgs,
  inputs,
  self,
  ...
}:
let
  keys = import "${self}/modules/nixos/keys.nix";
in
{
  imports = [
    # Tier bundle + foundation (same trio orin-nano/nasbook import directly,
    # and core-pi/hass-pi get transitively via rpi5-node.nix).
    "${self}/modules/nixos/base.nix"
    "${self}/modules/nixos/headless.nix"
    "${self}/modules/nixos/hosts.nix"
    "${self}/modules/nixos/persistence.nix"
    "${self}/modules/nixos/clevis-initrd.nix"

    "${self}/users/martin/nixos.nix"
    "${self}/modules/nixos/services/container-updater.nix"

    inputs.disko.nixosModules.disko
    ./disko.nix
    ./secrets.nix

    inputs.nix-presets.nixosModules.monitoring-node
    inputs.nix-presets.nixosModules.herdr-remote-client
  ];

  networking.hostName = "mac-mini";

  # Same fleet-wide key set as every other host (modules/nixos/keys.nix).
  # headless.nix only creates the user; each host authorizes its own keys.
  users.users.martin.openssh.authorizedKeys.keys = [
    keys.ssh.yubikey
    keys.ssh.fido2
    keys.ssh.fido2-backup
  ];
  users.users.root.openssh.authorizedKeys.keys = [
    keys.ssh.yubikey
    keys.ssh.fido2
    keys.ssh.fido2-backup
  ];

  # Old, comparatively slow CPU (2011 Sandy Bridge) — don't let nightly
  # auto-upgrade fall back to a multi-hour local compile if Attic ever misses.
  my.deploy.autoUpgrade = {
    enable = true;
    requireCache = true;
  };

  my.monitoring.node.enable = true;

  my.herdr-remote-client = {
    enable = true;
    serverIp = "10.0.0.5"; # nixos-nvme physical LAN IP (inventory.nix)
  };

  # Tang auto-unlock at boot — mandatory here, not optional: this host has no
  # physical keyboard/screen, ever, so a plain LUKS passphrase prompt would
  # hang forever with nobody able to answer it.
  #
  # `enable` is gated on the JWE existing rather than hardcoded true: the JWE
  # (nix-secrets/initrd/cryptroot_mac-mini.jwe) can only be generated AFTER
  # the real LUKS passphrase is set during the physical install (disko), so
  # it doesn't exist at the time this file is first committed. Once it's
  # generated — `scripts/generate-jwe.sh mac-mini`, same passphrase used
  # during disko format — this flips on automatically on the next
  # rebuild/redeploy; no further code change needed. Same pattern
  # hosts/nixos-nvme/hardware-boot.nix uses for its initrd SSH key.
  my.boot.clevis-initrd = {
    enable = builtins.pathExists (inputs.nix-secrets + "/initrd/cryptroot_mac-mini.jwe");
    luksDevice = "mac_mini_crypt";
    secretFile = inputs.nix-secrets + "/initrd/cryptroot_mac-mini.jwe";
    # hostIp left null (default) — DHCP in initrd, no static IP assigned yet.
  };

  environment.systemPackages = with pkgs; [
    sops
    age
    libfido2
  ];

  # Stateless root (impermanence) — same pattern as modules/nixos/rpi5-node.nix
  # (shared by core-pi/hass-pi). disko.nix only declares the real, disk-backed
  # mounts (ESP, /nix/persist); the ephemeral tmpfs "/" and "/var" are a
  # NixOS-only concept with no disk backing, so they're declared here instead.
  fileSystems = {
    "/" = lib.mkForce {
      device = "none";
      fsType = "tmpfs";
      options = [
        "defaults"
        "size=2G"
        "mode=755"
      ];
      neededForBoot = true;
    };
    "/var" = lib.mkForce {
      device = "none";
      fsType = "tmpfs";
      options = [
        "defaults"
        "size=2G"
        "mode=755"
      ];
      neededForBoot = true;
    };
    "/nix".neededForBoot = true;
    "/nix/persist".neededForBoot = true;
  };

  boot.loader.systemd-boot = {
    enable = true;
    # Same cap orin-nano uses — an unpruned ESP fills up with stale
    # per-generation kernels/initrds over time.
    configurationLimit = 10;
  };

  system.stateVersion = "25.11";
}
