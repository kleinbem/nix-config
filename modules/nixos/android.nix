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
      extraModulePackages = [ config.boot.kernelPackages.v4l2loopback ];
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
  };
}
