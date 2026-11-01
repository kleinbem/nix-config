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
      description = "Automatically start Shizuku daemon via udev/systemd when an Android device is connected via USB";
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
          # With System.map in the kernel's dev output, kbuild runs depmod for
          # out-of-tree modules, and v4l2loopback's own modules.alias collides
          # with the kernel's in aggregateModules. The aggregator runs depmod
          # anyway, so skip it here. A no-op once the package passes DEPMOD.
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

    # Auto-start Shizuku daemon via ADB when any fleet Android device is connected via USB
    services.udev.extraRules = lib.mkIf cfg.autoShizuku ''
      ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="12d1|04e8|18d1|2717|05c6|0bb4|1004|22b8", TAG+="systemd", ENV{SYSTEMD_WANTS}+="shizuku-auto.service"
    '';

    systemd.services.shizuku-auto = lib.mkIf cfg.autoShizuku {
      description = "Auto-start Shizuku daemon on connected Android devices via ADB";
      after = [ "network.target" ];
      serviceConfig = {
        Type = "oneshot";
        User = config.my.username;
        ExecStart = pkgs.writeShellScript "shizuku-auto-start" ''
          ADB="${pkgs.android-tools}/bin/adb"

          # Allow up to 10 seconds for ADB devices to register after USB plug
          for i in $(seq 1 10); do
            DEVS=$($ADB devices 2>/dev/null | grep -v "List" | grep "device$" | cut -f1 || true)
            if [ -n "$DEVS" ]; then
              break
            fi
            sleep 1
          done

          DEVS=$($ADB devices 2>/dev/null | grep -v "List" | grep "device$" | cut -f1 || true)
          if [ -z "$DEVS" ]; then
            echo "No authorized ADB devices found." >&2
            exit 0
          fi

          for SERIAL in $DEVS; do
            if $ADB -s "$SERIAL" shell ps -ef 2>/dev/null | grep -q "shizuku_server"; then
              echo "Shizuku server is already running on $SERIAL."
              continue
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
            ' || true
          done
        '';
      };
    };
  };
}
