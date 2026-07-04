{
  config,
  lib,
  pkgs,
  myInventory,
  ...
}:
let
  inherit (config.networking) hostName;
  otherHosts = lib.filterAttrs (name: _: name != hostName) myInventory.hosts;

  # Define container subnets per host
  subnets = {
    nixos-nvme = "10.85.46.0/24";
    nasbook = "10.85.47.0/24";
    core-pi = "10.85.48.0/24";
    hass-pi = "10.85.49.0/24";
  };

  # Generate routes to other hosts' container subnets
  routes = lib.mapAttrsToList (name: host: {
    address = lib.head (lib.splitString "/" subnets.${name});
    prefixLength = 24;
    via = host.ip;
    options = {
      onlink = "";
    };
  }) (lib.filterAttrs (name: _: subnets ? ${name} && otherHosts ? ${name}) otherHosts);

in
{
  networking.interfaces."${config.my.network.externalInterface}".ipv4.routes = routes;

  # NetworkManager often drops interface-defined static routes when managing interfaces.
  # This oneshot service enforces the routes dynamically via iproute2.
  systemd.services.enforce-container-routes = lib.mkIf (routes != [ ]) {
    description = "Enforce static routes to other container networks";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      ${lib.concatMapStringsSep "\n" (
        route:
        "${config.boot.kernelPackages.iproute2 or pkgs.iproute2}/bin/ip route replace ${route.address}/${toString route.prefixLength} via ${route.via} dev ${config.my.network.externalInterface} onlink || true"
      ) routes}
    '';
  };

  # Ensure IP forwarding is enabled if this host acts as a gateway for its containers
  boot.kernel.sysctl."net.ipv4.ip_forward" = lib.mkDefault 1;
}
