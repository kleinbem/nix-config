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

    inputs.nix-presets.nixosModules.container-common
    inputs.nix-presets.nixosModules.n8n
    inputs.nix-presets.nixosModules.attic
    inputs.nix-presets.nixosModules.code-server
    inputs.nix-presets.nixosModules.open-webui
    inputs.nix-presets.nixosModules.dashboard
    inputs.nix-presets.nixosModules.qdrant
    inputs.nix-presets.nixosModules.playground
    inputs.nix-presets.nixosModules.caddy
    inputs.nix-presets.nixosModules.comfyui
    inputs.nix-presets.nixosModules.langfuse
    inputs.nix-presets.nixosModules.langflow
    inputs.nix-presets.nixosModules.monitoring
    inputs.nix-presets.nixosModules.monitoring-node
    inputs.nix-presets.nixosModules.litellm
    inputs.nix-presets.nixosModules.loki
    inputs.nix-presets.nixosModules.crowdsec
    inputs.nix-presets.nixosModules.netdata
    inputs.nix-presets.nixosModules.authelia
    inputs.nix-presets.nixosModules.openclaw
    inputs.nix-presets.nixosModules.agent-zero
    inputs.nix-presets.nixosModules.agent-team
    inputs.nix-presets.nixosModules.cups
    inputs.nix-presets.nixosModules.github-runner
    inputs.nix-presets.nixosModules.ollama
    inputs.nix-presets.nixosModules.syncthing
    inputs.nix-presets.nixosModules.backup
    inputs.nix-presets.nixosModules.paperless
    inputs.nix-presets.nixosModules.claude

    "${self}/modules/nixos/services/github-runner.nix"
    "${self}/modules/nixos/services/cloudflare-tunnel.nix"
    "${self}/modules/nixos/persistence.nix"
    ./secrets.nix
    "${self}/modules/nixos/apps.nix"
    "${self}/modules/nixos/snapper.nix"
    "${self}/modules/nixos/disko.nix"
    "${self}/modules/nixos/data-disk.nix"
    inputs.disko.nixosModules.disko
    ./ai.nix
    ./specialisations.nix
    "${self}/modules/nixos/services/container-updater.nix"

    ./hardware-boot.nix
    ./network.nix
    ./containers.nix
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
    desktop.gnome.enable = true;
    desktop.claude.enable = true;
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

  # Shorten the boot menu label so specialisation names are visible in systemd-boot.
  system.nixos.label = lib.trivial.release;
  system.stateVersion = "25.11";

}
