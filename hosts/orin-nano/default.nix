# orin-nano — NVIDIA Jetson Orin Nano (aarch64)
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
    # Tier bundle + foundation
    "${self}/modules/nixos/base.nix"
    "${self}/modules/nixos/headless.nix"
    "${self}/modules/nixos/hosts.nix"

    # Edge-device modules orin needs (curated — default.nix's workstation
    # bundle would also pull in snapper/printing/security/android which
    # don't apply to this host).
    "${self}/modules/nixos/kernel.nix" # AI-tuned sysctl, BBR, swappiness
    "${self}/modules/nixos/audit.nix" # security audit rules
    "${self}/modules/nixos/users.nix" # sops-backed root password, mutableUsers=false
    "${self}/modules/nixos/ai-hardening.nix" # AI workload sandboxing
    "${self}/modules/nixos/ananicy.nix" # process scheduler
    "${self}/modules/nixos/scripts.nix" # verify-system helpers
    "${self}/modules/nixos/clevis-initrd.nix" # Tang/clevis LUKS unlock
    "${self}/modules/nixos/initrd-fan.nix" # spin fan during initrd (pre-OS thermal safety)

    "${self}/users/martin/nixos.nix"
    # Hardware support from our local hardware flake
    inputs.nix-hardware.nixosModules.orin-nano
    # Presets
    inputs.nix-presets.nixosModules.ollama
    inputs.nix-presets.nixosModules.llama-cpp
    inputs.nix-presets.nixosModules.frigate
    inputs.nix-presets.nixosModules.syncthing
    inputs.nix-presets.nixosModules.monitoring-node
    inputs.nix-presets.nixosModules.attic-push
    # Disko configuration
    inputs.disko.nixosModules.disko
    ./disko.nix
    ./secrets.nix
    "${self}/modules/nixos/persistence.nix"

    # Host-specific split modules
    ./hardware.nix
    ./network.nix
    ./services.nix
  ];

  networking.hostName = "orin-nano";

  # Orin Nano needs to compile its own kernel/L4T locally.
  # We do NOT set requireCache = true here, so there is no 30-minute timeout
  # to brutally kill the build. It will take as long as it needs.
  my.deploy.autoUpgrade = {
    enable = true;
  };

  my.attic-push = {
    enable = true;
    tokenFile = config.sops.secrets.attic_push_token.path;
  };

  nixpkgs = {
    hostPlatform = "aarch64-linux";
    config = {
      allowUnfree = true;
      allowUnfreePredicate = _: true;
      allowUnsupportedSystem = true;
    };
    overlays = [
      (final: _prev: {
        cudaPackages = final.cudaPackages_12_6;
        # Temporary fix for jetpack-nixos capsule updates failing on unstable
        bzip2_1_1 = final.bzip2;
      })
    ];
  };

  environment.systemPackages = with pkgs; [
    sops
    age
    libfido2

    inputs.jetpack-nixos.legacyPackages.${pkgs.stdenv.hostPlatform.system}.l4t-tools # Essential: provides tegrastats and L4T utilities
  ];

  nix.settings.trusted-users = [
    "root"
    "martin"
  ];

  # colmena deploys as martin (PermitRootLogin = "no" in security.nix)
  security.sudo.extraRules = [
    {
      users = [ "martin" ];
      commands = [
        {
          command = "ALL";
          options = [ "NOPASSWD" ];
        }
      ];
    }
  ];

  # Disable snapper — /nix is ext4 on this host, btrfs subvolumes cannot be created
  services.snapper.configs = lib.mkForce { };
  systemd.services.snapper-init-persist.enable = lib.mkForce false;

  # ClamAV is irrelevant on a headless edge node with no user-facing file ingestion
  services.clamav = {
    daemon.enable = lib.mkForce false;
    updater.enable = lib.mkForce false;
  };

  users.users = {
    martin.openssh.authorizedKeys.keys = [
      keys.ssh.yubikey
      keys.ssh.fido2
      keys.ssh.fido2-backup
    ];
    root.openssh.authorizedKeys.keys = [
      keys.ssh.yubikey
      keys.ssh.fido2
      keys.ssh.fido2-backup
    ];
  };

  # No desktop specialisation: orin-nano is a pure headless AI edge device.
  # Local debug is text-mode TTY on HDMI (agetty on tty1); remote work is SSH.
  # Need a remote Wayland app occasionally? `waypipe` it from your workstation.

  # Override headless.nix silent boot to keep console output visible.
  # HDMI (tty0) is BLACK during initrd on Jetson — the Tegra display driver
  # (nvidia-drm) only loads AFTER the LUKS unlock, so the passphrase prompt has
  # no framebuffer to render on. The Tegra debug UART (ttyTCU0, micro-USB debug
  # port) IS live from firmware, so list it LAST → it becomes the primary
  # /dev/console: the initrd/LUKS prompt is then visible AND enterable over
  # serial, while HDMI still shows everything once the system is up. Do NOT drop
  # ttyTCU0 again (an HDMI-only console makes a stale-JWE unlock failure an
  # invisible black-screen hang). See docs/ + the clevis-initrd setup.
  # This mkForce replaces the WHOLE kernelParams list, so anything NixOS or a
  # module would otherwise inject MUST be re-listed here or it is silently
  # dropped:
  #   - root=fstab       : systemd stage-1 mounts the tmpfs root via fstab;
  #                        without it → gpt-auto-root timeout → emergency mode.
  #   - systemd.machine_id: /etc/machine-id is NOT persisted under systemd-initrd
  #                        (persistence.nix), so without a fixed id here systemd
  #                        regenerates a random one every boot ("Detected first
  #                        boot" each time). Pin it. (nixos-nvme does the same.)
  # console=ttyTCU0 stays LAST so it is the primary /dev/console for the LUKS
  # prompt over the Tegra debug UART — do not reorder the console= entries.
  boot.kernelParams = lib.mkForce [
    "root=fstab"
    "systemd.machine_id=9fef3c9be6eb4bf29456f7be28ec4d6d"
    "console=tty0"
    "console=ttyTCU0,115200"
  ];

  system.stateVersion = "25.11";
}
