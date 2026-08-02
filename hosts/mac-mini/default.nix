# mac-mini — Mid-2011 Mac Mini (Macmini5,x), Intel, real 64-bit EFI.
#
# Role: dedicated interactive box (no physical keyboard/mouse/screen — GUI
# access is remote-desktop only). First concrete use case: join/record Zoom
# calls from a container. Provisioned like orin-nano/core-pi/hass-pi — SSD
# wiped+installed via USB-SATA adapter (see .just/deployment.just
# mac-mini-install-usb), then moved internally.
{
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

  # Wake-on-LAN TODO: this host has zero physical access (no keyboard/
  # screen/case access after it's mounted), so remote power-on would be
  # genuinely useful. Deliberately NOT wired up yet — the option
  # (networking.interfaces.<name>.wakeOnLan.enable) needs the real
  # interface name, which only exists after the onboard Broadcom NIC gets
  # its udev-assigned name on first boot. Set this once that's known.

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

  my = {
    # Old, comparatively slow CPU (2011 Sandy Bridge) — don't let nightly
    # auto-upgrade fall back to a multi-hour local compile if Attic ever misses.
    deploy.autoUpgrade = {
      enable = true;
      requireCache = true;
    };

    monitoring.node.enable = true;

    # Joins the unlock cluster as a 4th independent Tang server (alongside
    # nixos-nvme/core-pi/hass-pi/nasbook) — more fleet redundancy.
    services.tang.enable = true;

    # Keyless `netbird ssh mac-mini` — same convenience the rpi5 tier
    # (core-pi/hass-pi) has; regular pubkey SSH still works independently.
    services.netbird.allowServerSsh = true;

    herdr-remote-client = {
      enable = true;
      serverIp = "10.0.0.5"; # nixos-nvme physical LAN IP (inventory.nix)
    };

    # Tang auto-unlock at boot — mandatory here, not optional: this host has
    # no physical keyboard/screen, ever, so a plain LUKS passphrase prompt
    # would hang forever with nobody able to answer it.
    #
    # `enable` is gated on the JWE existing rather than hardcoded true: the
    # JWE (nix-secrets/initrd/cryptroot_mac-mini.jwe) can only be generated
    # AFTER the real LUKS passphrase is set during the physical install
    # (disko), so it doesn't exist at the time this file is first committed.
    # Once it's generated — `scripts/generate-jwe.sh mac-mini`, same
    # passphrase used during disko format — this flips on automatically on
    # the next rebuild/redeploy; no further code change needed. Same pattern
    # hosts/nixos-nvme/hardware-boot.nix uses for its initrd SSH key.
    boot.clevis-initrd = {
      enable = builtins.pathExists (inputs.nix-secrets + "/initrd/cryptroot_mac-mini.jwe");
      luksDevice = "mac_mini_crypt";
      secretFile = inputs.nix-secrets + "/initrd/cryptroot_mac-mini.jwe";
      fallbackMessage = "Tang still unreachable; falling back to initrd SSH (no physical console on this host)";
      # hostIp left null (default) — DHCP in initrd, no static IP assigned yet.
    };
  };

  # Initrd SSH fallback — same pattern as hosts/nixos-nvme/hardware-boot.nix.
  # mac-mini has zero physical keyboard/screen access, ever, so if Tang is
  # ever unreachable at boot the normal ask-password prompt would hang
  # forever with nobody able to answer it. This lets the passphrase be typed
  # in remotely instead. Gated on the key file existing, same convention as
  # clevis-initrd.enable above.
  boot.initrd.network = {
    enable = true;
    ssh = {
      enable = builtins.pathExists (inputs.nix-secrets + "/initrd/ssh_host_ed25519_key_mac-mini");
      port = 2222;
      authorizedKeys = [
        keys.ssh.yubikey
        keys.ssh.fido2
        keys.ssh.fido2-backup
      ];
      hostKeys = [ "/etc/ssh/ssh_host_ed25519_key_mac-mini" ];
    };
  };
  boot.initrd.secrets."/etc/ssh/ssh_host_ed25519_key_mac-mini" = lib.mkForce (
    inputs.nix-secrets + "/initrd/ssh_host_ed25519_key_mac-mini"
  );

  environment.systemPackages = with pkgs; [
    sops
    age
    libfido2
  ];

  # Real x86 hardware (2011 Mac Mini, Sandy Bridge i5-2415M) — same reasoning
  # as nixos-nvme: microcode security/stability fixes, and redistributable
  # firmware in case the internal Broadcom Wi-Fi/Bluetooth ever gets used.
  # NOT required for the onboard tg3 Ethernet (BCM57765 is in the
  # 57765_PLUS chip group, which brings the link up without a firmware
  # blob) — Tang-unlock-in-initrd doesn't depend on this.
  hardware = {
    enableRedistributableFirmware = true;
    cpu.intel.updateMicrocode = true;

    # VAAPI for the eventual Zoom-recording container workload — a 2-core
    # CPU wants encode/decode offloaded to the iGPU. `intel-vaapi-driver`
    # (legacy i965), NOT `intel-media-driver` (iHD): the latter only
    # supports Broadwell+/Gen8+, this is Sandy Bridge/Gen6. Encode
    # support on Gen6 via i965 is known to be flaky on Linux (decode is
    # solid) — untested until the actual container exists; enabled now
    # so it's ready to try.
    graphics = {
      enable = true;
      extraPackages = with pkgs; [ intel-vaapi-driver ];
    };
  };

  # (services.fwupd is already on fleet-wide via core.nix — LVFS almost
  # certainly has nothing for this specific hardware anyway: Apple's own
  # Boot ROM firmware isn't LVFS-published, and the Samsung SATA SSD is
  # out of scope too — but it's already there for whatever's plugged in
  # later, no host-specific override needed.)
  #
  # Boot ROM confirmed current as of the 2026-08-02 High Sierra install
  # (133.0.0.0.0) — the last firmware Apple ever shipped for Macmini5,x.
  # Not upgradable further, and not LVFS-managed (see above), so if
  # third-party-OS boot flakiness ever shows up here, stale firmware is
  # ruled out as the cause.

  # Fleet convention (rpi5-node.nix, nasbook, orin-nano): periodic TRIM
  # alongside disko's allowDiscards, not instead of it.
  services.fstrim.enable = true;

  # Join the NetBird mesh — same pattern as orin-nano/nasbook/core-pi/hass-pi
  # (modules/nixos/networking.nix netbird-autojoin, gated on netbird_setup_key
  # from secrets.nix).
  services.netbird.enable = true;

  # DNS was broken out of the box: modules/nixos/networking.nix defaults
  # networking.resolvconf.enable to true fleet-wide, and every OTHER host
  # overrides that (resolved.enable=true here like orin-nano, or forced off
  # like the rpi5 nodes) — mac-mini never got either override, so resolv.conf
  # pointed at a systemd-resolved stub (127.0.0.1) that was never enabled.
  services.resolved = {
    enable = true;
    settings.Resolve.FallbackDNS = "1.1.1.1 8.8.8.8";
    settings.Resolve.DNSSEC = "false";
  };
  networking.resolvconf.enable = lib.mkForce false;

  # Override the fleet-wide zstd zram default (core.nix): zstd's better
  # ratio costs more CPU per swap page than lz4, which matters more on
  # this 2-core CPU than on the rest of the fleet. 16GB RAM means this
  # host is unlikely to swap heavily anyway, so it's a marginal call —
  # revisit if the recording workload turns out to be swap-hungry.
  zramSwap.algorithm = lib.mkForce "lz4";

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
