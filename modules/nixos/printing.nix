{
  config,
  pkgs,
  lib,
  ...
}:

let
  # Relative path to driver wrapper in the parent folder
  # Relative path to driver wrapper in the hardware folder
  # Relative path to driver wrapper in the hardware folder
  ricohDriver = pkgs.ricoh-driver;
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
      listenAddresses = [ "*:631" ];
      allowFrom = [ "all" ];
      browsing = true;
      defaultShared = true;
      extraConf = ''
        DefaultEncryption Never
        ServerAlias *
      '';
      drivers = [ ricohDriver ];
    };

    # Open CUPS and Printer ports
    # Port 631 for CUPS, 9100 for AppSocket/JetDirect (Ricoh)
    networking = {
      firewall = {
        allowedTCPPorts = [
          631
          9100
        ];
        allowedUDPPorts = [ 631 ];
      };

      # Fix Routing: Ensure the PC talks directly to the 10.0.x.x subnet
      # This fixes the "Redirect Host" issue where traffic to the printer goes to the router first
      interfaces.wlo1.ipv4.routes = [
        {
          address = "10.0.0.0";
          prefixLength = 16;
        }
      ];
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
