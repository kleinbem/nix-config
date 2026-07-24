{
  config,
  pkgs,
  lib,
  ...
}:

# 3D printing (distinct from the CUPS paper printer in printing.nix).
# Slicers + LAN-mode discovery for Bambu Lab hardware (A1 mini).
#
# LAN mode: the printer broadcasts itself over SSDP (UDP 1990/2021) and mDNS.
# The slicer listens for those broadcasts to auto-discover the printer and to
# send prints / stream status. MQTT-over-TLS (8883), FTPS (990) and the
# chamber camera (6000) are outbound PC→printer connections, so they need no
# inbound firewall rule — only the discovery listeners do.

let
  cfg = config.my.services.threeDPrinting;
in
{
  options.my.services.threeDPrinting = {
    enable = lib.mkEnableOption "3D printing slicers + Bambu Lab LAN discovery";
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      # Slicers
      orca-slicer # Community fork — de-facto A1 mini slicer
      bambu-studio # Bambu Lab's official slicer

      # CAD / modelling
      openscad-unstable # Script-based CAD (nightly; stable openscad is the stale 2021.01)
      blender # Mesh modelling / sculpting
      # freecad dropped 2026-07-24: unused (reuse existing models, not authoring
      # complex parametric parts) and freecad-wayland is an uncached variant → a
      # 1-2h FreeCAD source compile in CI every nixpkgs bump. Stock `freecad`
      # (cached) is the swap-in if GUI parametric CAD is ever needed.
    ];

    # mDNS so the slicer can resolve the printer by name on the LAN.
    services.avahi = {
      enable = true;
      nssmdns4 = true;
      openFirewall = true; # opens UDP 5353
    };

    # SSDP discovery ports the Bambu firmware broadcasts on.
    networking.firewall.allowedUDPPorts = [
      1990
      2021
    ];
  };
}
