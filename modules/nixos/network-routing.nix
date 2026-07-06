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

  routes = lib.mapAttrsToList (name: host: {
    address = lib.head (lib.splitString "/" subnets.${name});
    prefixLength = 24;
    via = host.physicalIp or host.ip;
    options = {
      onlink = "";
    };
  }) (lib.filterAttrs (name: _: subnets ? ${name} && otherHosts ? ${name}) otherHosts);

in
{
  networking.interfaces."${config.my.network.externalInterface}".ipv4.routes = routes;

  # NetworkManager often drops interface-defined static routes when managing
  # interfaces — including ones this service already installed (observed
  # 2026-07-05 on nixos-nvme: routes gone ~15h after the boot-time run, taking
  # cache.kleinbem.dev down with a 502). So the oneshot runs at boot AND on a
  # timer: `ip route replace` is idempotent, and RemainAfterExit must stay off
  # or the timer can never re-trigger the "still active" unit.
  systemd.services.enforce-container-routes = lib.mkIf (routes != [ ]) {
    description = "Enforce static routes to other container networks";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
    };
    script = ''
      ${lib.concatMapStringsSep "\n" (
        route:
        "${
          config.boot.kernelPackages.iproute2 or pkgs.iproute2
        }/bin/ip route replace ${route.address}/${toString route.prefixLength} via ${route.via} dev ${config.my.network.externalInterface} onlink || true"
      ) routes}
    '';
  };

  systemd.timers.enforce-container-routes = lib.mkIf (routes != [ ]) {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "2min";
      OnUnitActiveSec = "5min";
    };
  };

  # Ensure IP forwarding is enabled if this host acts as a gateway for its containers
  boot.kernel.sysctl."net.ipv4.ip_forward" = lib.mkDefault 1;
}
