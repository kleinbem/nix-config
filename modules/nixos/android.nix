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
    enable = lib.mkEnableOption "Android tools (ADB, scrcpy)";
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      scrcpy
      android-tools # ADB, fastboot, etc.
      heimdall # Samsung flashing tool (optional, but good to have)
    ];

    # Ensure the user is in the adbusers group (already done in users.nix for martin, but safe here)
    users.users.${config.my.username}.extraGroups = [ "adbusers" ];
  };
}
