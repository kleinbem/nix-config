{
  pkgs,
  lib,
  config,
  inputs,
  self,
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

    "${self}/modules/nixos/services/github-runner.nix"
    "${self}/modules/nixos/services/cloudflare-tunnel.nix"
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
    ];
  };

  my = {
    security.ai-hardening.enable = true;
    monitoring.node.enable = true;
    services.tang.enable = true;
    deploy.autoUpgrade.enable = true;
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
    journald.extraConfig = ''
      SystemMaxUse=500M
      SystemMaxFileSize=50M
      MaxRetentionSec=1month
    '';
    pcscd.enable = true;
    fprintd.enable = true;
  };

  home-manager.users.${config.my.username} = import "${self}/users/martin/home.nix";
  home-manager.users.dhirujaan = import "${self}/users/dhirujaan/home.nix";

  # NOTE: the efi-boot-guard service lives in ./hardware-boot.nix (it also
  # enforces BootOrder). Don't redefine it here — systemd.services.<n>.script
  # is types.lines, so a second definition silently concatenates rather than
  # erroring, duplicating the restore/NVRAM logic.

  # Shorten the boot menu label so specialisation names are visible in systemd-boot.
  system.nixos.label = lib.trivial.release;
  system.stateVersion = "25.11";

}
