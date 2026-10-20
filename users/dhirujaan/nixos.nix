{
  config,
  lib,
  pkgs,
  secretFile,
  ...
}:
let
  # Password hash lives in kleinbem-secrets nix/shared.yaml under
  # `dhirujaan_password_hash` (mkpasswd -m yescrypt). Until that key
  # exists the account has NO password and cannot log in locally — the
  # old `initialPassword = "nix"` was permanent: with the fleet-wide
  # users.mutableUsers = false it is re-applied on every activation and
  # `passwd` cannot change it. Key presence is checked on the (plaintext)
  # key names so eval keeps working before the value is added; sops-nix
  # would otherwise fail activation on a missing key.
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
