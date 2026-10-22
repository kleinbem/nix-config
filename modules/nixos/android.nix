{
  pkgs,
  lib,
  config,
  ...
}:

let
  cfg = config.my.android;
in
{
  options.my.android = {
    enable = lib.mkEnableOption "Android tools (ADB, scrcpy, tablet integration)";

    loopbackCam = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable v4l2loopback kernel module and DroidCam for Android webcam/mic integration";
    };

    weylus = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable Weylus and uinput rules for tablet touch & stylus screen extension";
    };

    autoShizuku = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Automatically start Shizuku daemon via udev/systemd when MatePad Pro tablet is connected via USB";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages =
      with pkgs;
      [
        scrcpy
        android-tools # ADB, fastboot, etc.
        heimdall # Samsung flashing tool (optional, but good to have)
      ]
      ++ lib.optionals cfg.loopbackCam [
        droidcam # ships droidcam-cli too
      ]
      ++ lib.optionals cfg.weylus [
        weylus
      ];

    # Ensure the user is in the adbusers and uinput groups
    users.users.${config.my.username}.extraGroups = [
      "adbusers"
    ]
    ++ lib.optional cfg.weylus "uinput";

    # v4l2loopback kernel module creates /dev/video10 for DroidCam virtual camera
    boot = lib.mkIf cfg.loopbackCam {
      extraModulePackages =
        let
          inherit (config.boot.kernelPackages) v4l2loopback;
          # Since the nixpkgs bump to linux-zen 7.2.11 (nix-config #186) the
          # kernel's dev output ships System.map, so kbuild's modules_install
          # runs depmod for out-of-tree modules too. v4l2loopback then carries
          # its own lib/modules/<ver>/modules.alias and collides with the
          # kernel's in aggregateModules ("two given paths contain a
          # conflicting subpath") — the nixos-nvme toplevel on main stopped
          # building. The aggregator runs depmod over everything anyway, so
          # skip it here, the same way #191 does for the Orin's L4T modules.
          # Self-retiring: a no-op once the package passes DEPMOD itself.
          withoutDepmod =
            if lib.any (lib.hasPrefix "DEPMOD=") (v4l2loopback.makeFlags or [ ]) then
              v4l2loopback
            else
              v4l2loopback.overrideAttrs (old: {
                makeFlags = (old.makeFlags or [ ]) ++ [ "DEPMOD=true" ];
              });
        in
        [ withoutDepmod ];
      kernelModules = [
        "v4l2loopback"
        "snd-aloop"
      ];
      extraModprobeConfig = ''
        options v4l2loopback devices=1 video_nr=10 card_label="DroidCam" exclusive_caps=1
      '';
    };

    # Uinput permissions for Weylus stylus/touch injection
    hardware.uinput.enable = lib.mkIf cfg.weylus true;

    # Open companion ports on the NetBird mesh interface (wt0) so tablet/phone can
    # reach Weylus, GNOME RDP, and DroidCam when untethered from USB.
    networking.firewall.interfaces."wt0" = {
      allowedTCPPorts =
        lib.optionals cfg.weylus [
          1701 # Weylus stylus/touch
          3389 # GNOME RDP virtual display
        ]
        ++ lib.optionals cfg.loopbackCam [
          4747 # DroidCam video/audio feed
        ];
    };

    # Auto-start Shizuku daemon via ADB when MatePad Pro USB is connected
    services.udev.extraRules = lib.mkIf cfg.autoShizuku ''
      ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="12d1", ATTR{idProduct}=="107e", ATTR{serial}=="QBK6R20825000010", TAG+="systemd", ENV{SYSTEMD_WANTS}+="shizuku-matepad.service"
    '';

    systemd.services.shizuku-matepad = lib.mkIf cfg.autoShizuku {
      description = "Auto-start Shizuku daemon on MatePad Pro via ADB";
      after = [ "network.target" ];
      serviceConfig = {
        Type = "oneshot";
        User = config.my.username;
        ExecStart = pkgs.writeShellScript "shizuku-matepad-start" ''
          SERIAL="QBK6R20825000010"
          ADB="${pkgs.android-tools}/bin/adb"

          for i in $(seq 1 15); do
            if $ADB devices | grep -q "$SERIAL.*device"; then
              break
            fi
            sleep 1
          done

          if ! $ADB devices | grep -q "$SERIAL.*device"; then
            echo "Device $SERIAL not found or not authorized via ADB" >&2
            exit 0
          fi

          if $ADB -s "$SERIAL" shell ps -ef | grep -q "shizuku_server"; then
            echo "Shizuku server is already running on $SERIAL."
            exit 0
          fi

          echo "Starting Shizuku on $SERIAL..."
          $ADB -s "$SERIAL" shell '
            APK_PATH=$(pm path moe.shizuku.privileged.api 2>/dev/null | cut -d: -f2 | head -n 1)
            if [ -n "$APK_PATH" ]; then
              LIB_DIR="$(dirname "$APK_PATH")/lib/arm64"
              if [ -f "$LIB_DIR/libshizuku.so" ]; then
                "$LIB_DIR/libshizuku.so"
              fi
            fi
          '
        '';
      };
    };
  };
}
