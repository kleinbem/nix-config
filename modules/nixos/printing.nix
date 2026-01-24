{
  config,
  pkgs,
  lib,
  ...
}:

let
  # Relative path to driver wrapper in the parent folder
  # Relative path to driver wrapper in the hardware folder
  ricohDriver = pkgs.callPackage ./hardware/ricoh-driver.nix { };
  cfg = config.my.services.printing;
in
{
  options.my.services.printing = {
    enable = lib.mkEnableOption "Printing Services";
  };

  config = lib.mkIf cfg.enable {
    services.printing = {
      enable = true;
      logLevel = "debug";
      drivers = [ ricohDriver ];
    };

    hardware.printers = {
      ensurePrinters = [
        {
          name = "Ricoh_SP_220Nw";
          deviceUri = "socket://10.0.5.10:9100";
          model = "ricoh/RICOH-SP-220Nw.ppd";
          ppdOptions = {
            PageSize = "A4";
          };
        }
      ];
      ensureDefaultPrinter = "Ricoh_SP_220Nw";
    };
  };
}
