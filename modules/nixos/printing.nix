{
  config,
  pkgs,
  lib,
  ...
}:

let
  # Ricoh printer driver package from nix-packages overlay
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
      startWhenNeeded = false; # Fix socket clash on port 631
      logLevel = "info";
      listenAddresses = [ "*:631" ];
      allowFrom = [ "all" ];
      browsing = true;
      # no-link: cups-browsed fails to generate PPDs for printers with partial IPP attributes (missing media-col-default) and creates broken ///dev/null dummy queues
      browsed.enable = false;
      defaultShared = true;
      extraConf = ''
        DefaultEncryption Never
        ServerAlias *
        # no-link: permanent local policy: discard failing print jobs rather than stopping the queue indefinitely
        ErrorPolicy abort-job
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
          # no-link: IPP/1.0 legacy compatibility mode forces atomic Print-Job; Ricoh SP 220Nw firmware rejects chunked IPP/2.0 Send-Document with client-error-not-possible
          deviceUri = "ipp://10.0.5.10:631/ipp/print?version=1.0";
          model = "ricoh/RICOH-SP-220Nw.ppd";
          ppdOptions = {
            PageSize = "A4";
            ColorModel = "Gray";
          };
        }
      ];
      ensureDefaultPrinter = "Ricoh_SP_220Nw";
    };
  };
}
