{
  config,
  pkgs,
  lib,
  ...
}:

# 3D printing: slicers and LAN-mode discovery for the Bambu Lab A1 mini.
# Only discovery (SSDP, mDNS) needs inbound ports; MQTT, FTPS and the camera
# are outbound connections to the printer.

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
      stable.freecad # Stock cached variant pinned to stable

      # 3D Utilities, Viewers & Mesh Repair
      # f3d # Fast terminal/GUI 3D file viewer (disabled: upstream vtk-9.5.2 PEGTL build failure)
      meshlab # Advanced mesh processing, polygon reduction & manifold repair
      assimp # Command-line 3D format converter (STEP <-> STL <-> OBJ <-> GLTF)
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
