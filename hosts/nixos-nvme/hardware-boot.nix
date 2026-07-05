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
  # --- Stateless Root / Var ---
  fileSystems = {
    "/" = lib.mkForce {
      device = "none";
      fsType = "tmpfs";
      options = [
        "defaults"
        "size=4G"
        "mode=755"
      ];
      neededForBoot = true;
    };

    "/var" = lib.mkForce {
      device = "none";
      fsType = "tmpfs";
      options = [
        "defaults"
        "size=8G"
        "mode=755"
      ];
      neededForBoot = true;
    };

    "/nix".neededForBoot = true;
    "/nix/persist".neededForBoot = true;
  };

  my.boot.clevis-initrd = {
    enable = true;
    luksDevice = "cryptroot";
    secretFile = "${./cryptroot.jwe}";
    fallbackMessage = "Tang still unreachable; continuing (FIDO2 or passphrase fallback)";
  };

  boot = {
    kernelPackages = pkgs.linuxPackages_zen;
    # Force the JMicron JMS581 (152d:0581) USB-NVMe bridge out of UAS into BOT mode.
    # Its UAS firmware resets under sustained write load, causing I/O errors and
    # filesystem corruption when provisioning the Orin SSD over the USB enclosure.
    kernelParams = [
      "usb-storage.quirks=152d:0581:u"
      "systemd.machine_id=875e6f722d80415e955ebddd39206430"
    ];
    initrd = {
      availableKernelModules = [
        "nvme"
        "xhci_pci"
        "thunderbolt"
        "usb_storage"
        "sd_mod"
        "ahci"
      ];
      kernelModules = [
        "usbhid"
        "hid_generic"
        "e1000e" # Intel Ethernet — must load eagerly so networkd can bring up eno2 for Tang
      ];
      network = {
        enable = true;
        ssh = {
          enable = builtins.pathExists (inputs.nix-secrets + "/initrd/ssh_host_ed25519_key_nixos-nvme");
          port = 2222;
          authorizedKeys = [
            keys.ssh.yubikey
            keys.ssh.fido2
            keys.ssh.fido2-backup
          ];
          hostKeys = [ "/etc/ssh/ssh_host_ed25519_key_nixos-nvme" ];
        };
      };
      secrets."/etc/ssh/ssh_host_ed25519_key_nixos-nvme" = lib.mkForce (
        inputs.nix-secrets + "/initrd/ssh_host_ed25519_key_nixos-nvme"
      );
      systemd = {
        enable = true;
        tpm2.enable = true;
      };
      services.lvm.enable = true;
      services.udev.rules = ''
        # Prevent early-boot hangs (emergency shell) caused by empty USB storage readers
        # Generic USB2.0 Card Reader
        SUBSYSTEM=="block", ATTRS{idVendor}=="0bda", ATTRS{idProduct}=="0153", ENV{SYSTEMD_READY}="0"
        # USB to SATA/PCIe Bridge (External Harddisk Reader)
        SUBSYSTEM=="block", ATTRS{idVendor}=="152d", ATTRS{idProduct}=="0581", ENV{SYSTEMD_READY}="0"
      '';
      luks.devices.cryptroot.keyFileTimeout = 2;
    };

    # Clevis LUKS auto-unlock: fetches key from Tang servers on the LAN.
    # Only works when ethernet is plugged in. FIDO2 (YubiKey touch) is the
    # primary interactive unlock when on WiFi / undocked.

    loader = {
      systemd-boot.enable = lib.mkForce false;
      efi.canTouchEfiVariables = true;
    };
    lanzaboote = {
      enable = true;
      pkiBundle = "/nix/persist/var/lib/sbctl";
      configurationLimit = 15;
    };
    # Kernel parameters now handled by kernel.nix and audit.nix
    # i915 enhancements moved to kernel.nix
    tmp.useTmpfs = true;
    tmp.tmpfsSize = "8G";
  };

  nix = {
    # Distributed Builds: Offload aarch64 compilation to remote ARM nodes
    distributedBuilds = false;
    # buildMachines = [
    #   {
    #     hostName = "10.0.0.21"; # hass-pi static IP
    #     system = "aarch64-linux";
    #     protocol = "ssh-ng";
    #     maxJobs = 4;
    #     speedFactor = 2;
    #     supportedFeatures = [
    #       "nixos-test"
    #       "benchmark"
    #       "big-parallel"
    #       "kvm"
    #     ];
    #     mandatoryFeatures = [ ];
    #     sshKey = "/root/.ssh/id_ed25519"; # Daemon needs a non-Yubikey SSH key to connect silently
    #   }
    # ];
    # settings.extra-sandbox-paths = [ "/run/binfmt" ];
  };

  # Cross-compilation: fallback to emulation if Orin is offline
  boot.binfmt.emulatedSystems = [ "aarch64-linux" ];
  # boot.binfmt.registrations."aarch64-linux".fixBinary = true; # Required for disko-install chroot

  hardware = {
    cpu.intel.updateMicrocode = true;
    enableRedistributableFirmware = true;
    graphics = {
      enable = true;
      extraPackages = with pkgs; [
        intel-media-driver
        intel-compute-runtime
        libvdpau-va-gl
      ];
    };
  };

  services = {
    udev.packages = [
      pkgs.yubikey-personalization
      pkgs.libfido2
    ];
    udev.extraRules = ''
      # Use kyber scheduler for NVMe to improve latency
      ACTION=="add|change", KERNEL=="nvme*", ATTR{queue/scheduler}="kyber"
    '';
    fwupd.enable = true;
    irqbalance.enable = true;
    btrfs.autoScrub = {
      enable = true;
      interval = "weekly";
      fileSystems = [
        "/home"
        "/nix"
      ];
    };
    fstrim.enable = true;

    # --- High-Performance Scheduling (Official Nixpkgs) ---
    scx = {
      enable = true;
      # lavd over rusty on this box: rusty's load balancing is built around
      # AMD CCX/NUMA domains and treats all cores as equal; lavd is
      # latency-criticality aware WITH hybrid-core (P/E) support — on the
      # i3-1315U (2P+4E) it keeps interactive tasks on P-cores while builds
      # and containers ride the E-cores. If a BPF scheduler ever misbehaves,
      # the kernel auto-evicts it and falls back to EEVDF (safe to experiment).
      scheduler = "scx_lavd";
    };
  };

  systemd.services = {
    # Windows overwrites \EFI\BOOT\BOOTX64.EFI and can drop the NVRAM entry
    # on every Windows session, making NixOS invisible in the BIOS boot menu.
    # This service runs after each successful NixOS boot to restore both.
    efi-boot-guard = {
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
        gnused # sed (BootOrder parsing)
        efibootmgr
        util-linux # findmnt, lsblk
      ];
      script = ''
        SYSTEMD_BOOT="/boot/EFI/systemd/systemd-bootx64.efi"
        FALLBACK="/boot/EFI/BOOT/BOOTX64.EFI"

        # Restore the UEFI fallback path to systemd-boot. UEFI spec requires
        # firmware to try \EFI\BOOT\BOOTX64.EFI even with no NVRAM entries,
        # so keeping it as systemd-boot guarantees NixOS is always reachable.
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

        # Enforce boot ORDER. The re-create above front-loads a freshly created
        # entry, but if Windows left the "Linux Boot Manager" entry intact and
        # merely reordered it behind "Windows Boot Manager", the machine still
        # boots Windows by default. Put Linux Boot Manager first whenever it
        # isn't already.
        LBM=$(efibootmgr | sed -n 's/^Boot\([0-9A-Fa-f]\{4\}\)\*\? Linux Boot Manager$/\1/p' | head -1)
        if [ -n "$LBM" ]; then
          ORDER=$(efibootmgr | sed -n 's/^BootOrder: //p')
          if [ "''${ORDER%%,*}" != "$LBM" ]; then
            echo "efi-boot-guard: Linux Boot Manager ($LBM) not first in BootOrder; fixing"
            REST=$(printf '%s' "$ORDER" | tr ',' '\n' | grep -vix "$LBM" | paste -sd,)
            efibootmgr -o "$LBM''${REST:+,$REST}" || true
          fi
        fi
      '';
    };
  };
}
