{
  config,
  lib,
  myInventory,
  ...
}:

let
  cfg = config.my.services.cloudflareTunnel;
  caddy = "https://${myInventory.network.nodes.caddy.ip}:443";

  # Every `public = true` inventory node gets its `domain` routed to Caddy.
  # Mesh-only services leave `public` unset and are reached over NetBird
  # (nix/infra/netbird/dns.tf); anything else hits the 404 default.
  publicNodes = lib.filterAttrs (_: n: n.public or false) myInventory.network.nodes;
in
{
  options.my.services.cloudflareTunnel = {
    enable = lib.mkEnableOption "Cloudflare tunnel connecting public domains to the Caddy gateway";
  };

  config = lib.mkIf cfg.enable {
    assertions = lib.mapAttrsToList (name: n: {
      assertion = n ? domain && n ? externalPort;
      message = "inventory node `${name}` is public = true but lacks `domain` or `externalPort` — Caddy wouldn't have a vhost for it, so the tunnel route would dead-end.";
    }) publicNodes;

    services.cloudflared = {
      enable = true;
      tunnels = {
        "core-pi" = {
          credentialsFile = config.sops.templates."cloudflare-tunnel-credentials.json".path;
          originRequest = {
            noTLSVerify = true;
          };
          # Caddy's staticSites (the MTA-STS policy) aren't
          # inventory nodes, so route them here too.
          ingress =
            lib.mapAttrs (_: _: caddy) (config.my.containers.caddy.staticSites or { })
            // lib.mapAttrs' (_: n: lib.nameValuePair n.domain caddy) publicNodes;
          default = "http_status:404";
        };
      };
    };

    systemd.services."cloudflared-tunnel-core-pi".serviceConfig = {
      # Hardening / STIG baseline
      CapabilityBoundingSet = "";
      DevicePolicy = "closed";
      LockPersonality = true;
      MemoryDenyWriteExecute = true;
      NoNewPrivileges = true;
      PrivateDevices = true;
      PrivateTmp = true;
      ProtectClock = true;
      ProtectControlGroups = true;
      ProtectHome = true;
      ProtectHostname = true;
      ProtectKernelLogs = true;
      ProtectKernelModules = true;
      ProtectKernelTunables = true;
      ProtectProc = "invisible";
      ProtectSystem = "strict";
      RestrictAddressFamilies = [
        "AF_INET"
        "AF_INET6"
        "AF_UNIX"
      ];
      RestrictNamespaces = true;
      RestrictRealtime = true;
      RestrictSUIDSGID = true;
      SystemCallArchitectures = "native";
      SystemCallFilter = [
        "@system-service"
        "~@privileged"
      ];
    };
  };
}
