{ pkgs, ... }:

let
  # Relative path to driver wrapper in the parent folder
  # Relative path to driver wrapper in the hardware folder
  ricohDriver = pkgs.callPackage ./hardware/ricoh-driver.nix { };
in
{
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
}
