{
  config,
  lib,
  ...
}:

let
  cfg = config.my.services.ai;
in
{
  options.my.services.ai = {
    enable = lib.mkEnableOption "AI Services";
  };

  config = lib.mkIf cfg.enable {
    # Deprecated: AI Services are now containerized (see hosts/nixos-nvme/default.nix)
    # Keeping this module shell for future expansion if needed.
  };
}
