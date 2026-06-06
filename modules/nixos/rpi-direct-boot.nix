{
  pkgs,
  config,
  lib,
  ...
}:

let
  cfg = config.my.hardware.rpi-direct-boot;
in
{
  options.my.hardware.rpi-direct-boot = {
    enable = lib.mkEnableOption "Direct Kernel Boot for Raspberry Pi";
    dtbName = lib.mkOption {
      type = lib.types.str;
      default = "broadcom/bcm2712-rpi-5-b.dtb";
      description = "Path to the DTB relative to the dtbs directory";
    };
  };

  config = lib.mkIf cfg.enable {
    # Disable the default extlinux builder because we don't want extlinux.conf
    boot.loader.generic-extlinux-compatible.enable = lib.mkForce false;

    # We define our own bootloader installer script
    system.build.installBootLoader = pkgs.writeScript "install-rpi-bootloader" ''
      #!${pkgs.bash}/bin/bash
      set -euo pipefail

      # The first argument is the path to the newly built system profile
      # e.g., /nix/store/...-nixos-system-...
      SYSTEM_DIR="$1"
      ESP="/boot"

      echo "🚀 Installing direct kernel boot files to $ESP..."

      # We need to copy the kernel, initrd, and dtb to static paths so config.txt
      # can find them without needing to be updated.
      cp -fL "$SYSTEM_DIR/kernel" "$ESP/Image"
      cp -fL "$SYSTEM_DIR/initrd" "$ESP/initrd"

      # Handle the DTB
      DTB_SRC="$SYSTEM_DIR/dtbs/${cfg.dtbName}"
      DTB_DST="$ESP/$(basename "${cfg.dtbName}")"
      if [ -f "$DTB_SRC" ]; then
          cp -fL "$DTB_SRC" "$DTB_DST"
      else
          echo "⚠️ Warning: DTB $DTB_SRC not found!"
      fi

      # Update cmdline.txt with the new kernel parameters and init path
      PARAMS="$(cat "$SYSTEM_DIR/kernel-params")"
      echo "init=$SYSTEM_DIR/init $PARAMS" > "$ESP/cmdline.txt"

      # Ensure everything is synced to disk
      sync

      echo "✅ Raspberry Pi bootloader update complete."
    '';
  };
}
