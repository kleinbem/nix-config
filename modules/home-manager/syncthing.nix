{
  lib,
  config,
  pkgs,
  ...
}:
{
  options.modules.syncthing = {
    enable = lib.mkEnableOption "Syncthing file synchronization";
    vaultPath = lib.mkOption {
      type = lib.types.str;
      default = "${config.home.homeDirectory}/Notes";
      description = "Path to the primary Obsidian vault";
    };
  };

  config = lib.mkIf config.modules.syncthing.enable {
    services.syncthing = {
      enable = true;
      tray.enable = true;
    };

    # Ensure the vault directory exists
    home.activation.createVaultDir = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      mkdir -p "${config.modules.syncthing.vaultPath}"
    '';

    # Optional: Add syncthing to system packages for CLI access
    home.packages = [ pkgs.syncthing ];
  };
}
