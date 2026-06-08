{
  config,
  pkgs,
  lib,
  ...
}:

let
  cfg = config.my.hardware.rpi-direct-boot;
in
{
  options.my.hardware.rpi-direct-boot = {
    enable = lib.mkEnableOption "Raspberry Pi Direct Boot integration (Dynamic Hashed Paths)";
  };

  config = lib.mkIf cfg.enable {
    # 1. We MUST enable extlinux-compatible so NixOS generates the generations in /boot/nixos/
    boot.loader.generic-extlinux-compatible.enable = lib.mkForce true;
    boot.loader.generic-extlinux-compatible.configurationLimit = 3;

    # 2. Systemd Path unit to watch for extlinux.conf changes
    systemd.paths.sync-rpi-boot = {
      description = "Watch for extlinux.conf changes to update Raspberry Pi config.txt";
      wantedBy = [ "multi-user.target" ];
      pathConfig.PathChanged = "/boot/extlinux/extlinux.conf";
    };

    # 3. Systemd Service that parses extlinux.conf and writes config.txt
    systemd.services.sync-rpi-boot = {
      description = "Sync Raspberry Pi config.txt with extlinux.conf";

      path = [
        pkgs.gawk
        pkgs.coreutils
      ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };

      script = ''
                ESP="/boot"
                CONF="$ESP/extlinux/extlinux.conf"

                if [ ! -f "$CONF" ]; then
                  echo "extlinux.conf not found. Skipping sync."
                  exit 0
                fi

                echo "🔄 Detected extlinux.conf update. Syncing to Raspberry Pi config.txt..."

                # Extract the DEFAULT label
                DEFAULT_LABEL=$(awk '/^DEFAULT/ {print $2}' "$CONF")

                if [ -z "$DEFAULT_LABEL" ]; then
                  echo "❌ Could not find DEFAULT label in $CONF"
                  exit 1
                fi

                # Extract the LINUX, INITRD, FDT, and APPEND paths for the DEFAULT label
                KERNEL_PATH=$(awk -v label="$DEFAULT_LABEL" '
                  $1 == "LABEL" { in_label = ($2 == label) }
                  in_label && $1 == "LINUX" { print $2; exit }
                ' "$CONF")

                INITRD_PATH=$(awk -v label="$DEFAULT_LABEL" '
                  $1 == "LABEL" { in_label = ($2 == label) }
                  in_label && $1 == "INITRD" { print $2; exit }
                ' "$CONF")

                FDT_PATH=$(awk -v label="$DEFAULT_LABEL" '
                  $1 == "LABEL" { in_label = ($2 == label) }
                  in_label && $1 == "FDT" { print $2; exit }
                ' "$CONF")

                APPEND_TEXT=$(awk -v label="$DEFAULT_LABEL" '
                  $1 == "LABEL" { in_label = ($2 == label) }
                  in_label && $1 == "APPEND" { 
                    # Print everything after the APPEND keyword
                    $1=""; print substr($0,2); exit 
                  }
                ' "$CONF")

                # Strip leading slashes or ../ to make paths relative to the FAT32 root
                KERNEL_PATH=''${KERNEL_PATH#../}
                INITRD_PATH=''${INITRD_PATH#../}
                FDT_PATH=''${FDT_PATH#../}
                KERNEL_PATH=''${KERNEL_PATH#/}
                INITRD_PATH=''${INITRD_PATH#/}
                FDT_PATH=''${FDT_PATH#/}

                echo "Kernel:  $KERNEL_PATH"
                echo "Initrd:  $INITRD_PATH"
                echo "DTB:     $FDT_PATH"
                echo "Cmdline: $APPEND_TEXT"

                # Update cmdline.txt
                echo "$APPEND_TEXT" > "$ESP/cmdline.txt"

                # Update config.txt
                cat > "$ESP/config.txt" <<EOF
        [all]
        kernel=$KERNEL_PATH
        initramfs $INITRD_PATH followkernel
        cmdline=cmdline.txt
        arm_64bit=1
        upstream_kernel=1
        device_tree=$FDT_PATH
        dtparam=pciex1_gen=3
        os_check=0
        disable_splash=1
        hdmi_force_hotplug=1
        EOF

                sync
                echo "✅ Raspberry Pi boot files successfully synced."
      '';
    };
  };
}
