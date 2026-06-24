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
    deploy.autoUpgrade.enable = true;
    desktop.gnome.enable = true;
    desktop.claude.enable = true;
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

  # Windows (dual-boot on this NVMe — needed natively for locked-down exam
  # browsers) overwrites \EFI\BOOT\BOOTX64.EFI and can drop the "Linux Boot
  # Manager" NVRAM entry on a Windows session, making NixOS invisible in the
  # firmware boot menu. Re-assert both after each successful NixOS boot so the
  # system stays reachable regardless of what Windows did.
  systemd.services.efi-boot-guard = {
    description = "Restore EFI fallback path and NVRAM entry after Windows rewrites them";
    wantedBy = [ "multi-user.target" ];
    after = [ "local-fs.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    path = with pkgs; [
      coreutils
      diffutils # cmp
      gnugrep # grep
      efibootmgr
      util-linux # findmnt, lsblk
    ];
    script = ''
      SYSTEMD_BOOT="/boot/EFI/systemd/systemd-bootx64.efi"
      FALLBACK="/boot/EFI/BOOT/BOOTX64.EFI"

      # UEFI firmware always tries \EFI\BOOT\BOOTX64.EFI even with no NVRAM
      # entry, so keeping that fallback pointed at systemd-boot guarantees
      # NixOS is reachable after Windows clobbers it.
      if [ -f "$SYSTEMD_BOOT" ]; then
        if ! cmp -s "$SYSTEMD_BOOT" "$FALLBACK" 2>/dev/null; then
          echo "efi-boot-guard: restoring EFI fallback path to systemd-boot"
          mkdir -p "$(dirname "$FALLBACK")"
          cp "$SYSTEMD_BOOT" "$FALLBACK"
        fi
      fi

      # Re-register the NVRAM entry if Windows removed it.
      if ! efibootmgr | grep -q "Linux Boot Manager"; then
        echo "efi-boot-guard: NVRAM entry missing, re-registering..."
        ESP_DEV=$(findmnt -n -o SOURCE /boot)
        DISK=$(lsblk -dnpo PKNAME "$ESP_DEV")
        PART_NUM=$(lsblk -no PARTN "$ESP_DEV")
        efibootmgr --create \
          --disk "$DISK" \
          --part "$PART_NUM" \
          --label "Linux Boot Manager" \
          --loader '\EFI\systemd\systemd-bootx64.efi' \
          --unicode || true
      fi
    '';
  };

  # Shorten the boot menu label so specialisation names are visible in systemd-boot.
  system.nixos.label = lib.trivial.release;
  system.stateVersion = "25.11";

}
