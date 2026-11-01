{
  config,
  lib,
  pkgs,
  secretFile,
  ...
}:
let
  # Hash in nix/shared.yaml as `dhirujaan_password_hash` (mkpasswd -m yescrypt).
  # Until it exists the account has no password. Not initialPassword: with
  # mutableUsers = false it's reapplied on every activation. Gated on the key
  # name so a missing key can't fail activation.
  sharedSops = secretFile "nix/shared.yaml";
  hasPasswordHash =
    builtins.pathExists sharedSops
    && lib.hasInfix "\ndhirujaan_password_hash:" ("\n" + builtins.readFile sharedSops);
in
{
  users.users.dhirujaan = {
    isNormalUser = true;
    description = "Secondary User Session";
    extraGroups = [
      "video"
      "render"
      "networkmanager"
    ];
    hashedPasswordFile = lib.mkIf hasPasswordHash config.sops.secrets.dhirujaan_password_hash.path;
    # Linger allows services to run even when not logged in (needed for some nested setups)
    linger = true;
  };

  sops.secrets.dhirujaan_password_hash = lib.mkIf hasPasswordHash {
    neededForUsers = true;
  };

  # Enable Sway for this user (lightweight alternative)
  programs.sway = {
    enable = true;
    extraPackages = with pkgs; [
      swaylock
      swayidle
      wl-clipboard
      mako # notification daemon
      alacritty # lightweight terminal
      waybar # status bar
    ];
  };
}
