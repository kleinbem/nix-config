# Container Host Module
#
# Provides common setup for devices that host containers (core-pi, mac-mini, etc.)
# Handles networking, persistence, and container-updater orchestration.
#
# Usage in host config:
#
#   imports = [
#     "${self}/modules/nixos/container-host.nix"
#     "${self}/modules/nixos/services/container-updater.nix"  # Must also import this
#   ];
#
#   my.container-host = {
#     enable = true;
#     subnet = "10.85.48.0/24";
#     hostAddress = "10.85.48.1";
#     excludeFromUpdater = [ "attic" "caddy" "crowdsec" ];
#   };
#
#   my.containers = {
#     caddy = {
#       enable = true;
#       ip = "${myInventory.network.nodes.caddy.ip}/24";
#       hostDataDir = "/var/lib/caddy";
#     };
#     # ... more containers
#   };

{
  config,
  lib,
  ...
}:

let
  cfg = config.my.container-host;
in
{
  options.my.container-host = {
    enable = lib.mkEnableOption "Container Host (LXD networking, persistence, auto-update)";

    subnet = lib.mkOption {
      type = lib.types.str;
      description = "Container subnet (e.g., 10.85.48.0/24)";
      example = "10.85.48.0/24";
    };

    hostAddress = lib.mkOption {
      type = lib.types.str;
      description = "Host bridge IP on container subnet";
      example = "10.85.48.1";
    };

    bridge = lib.mkOption {
      type = lib.types.str;
      default = "cbr0";
      description = "Container bridge name";
    };

    excludeFromUpdater = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Containers to exclude from nightly auto-update (e.g., ['attic' 'caddy'])";
      example = [
        "attic"
        "caddy"
        "crowdsec"
      ];
    };

    enablePersistence = lib.mkEnableOption "Impermanence for container host" // {
      default = true;
    };
  };

  config = lib.mkIf cfg.enable {
    # ─── Container Networking ───────────────────────────────────
    my.network = {
      inherit (cfg) subnet hostAddress;
    };

    # ─── Firewall Rules for Container Traffic ───────────────────
    # Allow container traffic on the bridge
    networking.firewall = {
      extraForwardRules = ''
        # Allow traffic between containers on bridge
        iifname "${cfg.bridge}" oifname "${cfg.bridge}" accept
        # Allow containers to reach external networks
        iifname "${cfg.bridge}" accept
        oifname "${cfg.bridge}" accept
      '';
    };

    # ─── Container Auto-Update Orchestration (ADR 002) ──────────
    # Containers are decoupled from host generation and refreshed
    # nightly from CI-published manifest (eval-free on edge devices).
    # NOTE: Requires services/container-updater.nix to be imported.
    my.services.container-updater = {
      enable = true;
      containers =
        let
          allEnabled = lib.attrNames (lib.filterAttrs (_: v: v.enable or false) config.my.containers);
        in
        lib.subtractLists cfg.excludeFromUpdater allEnabled;
    };

    # ─── Persistence for Container State ────────────────────────
    # Container data directories are preserved across reboots
    # (especially important on impermanent hosts like core-pi)
    environment.persistence = lib.mkIf cfg.enablePersistence {
      "/nix/persist" = {
        directories =
          let
            # Extract all hostDataDir values from enabled containers
            containerDirs = lib.concatMap (
              name:
              (
                let
                  container = config.my.containers.${name};
                in
                if container.enable or false then
                  lib.optional (container ? hostDataDir) container.hostDataDir
                else
                  [ ]
              )
            ) (lib.attrNames config.my.containers);
          in
          lib.unique containerDirs;
      };
    };

    # ─── Systemd Service Dependencies ────────────────────────────
    # Ensure container networking is up before containers start
    systemd.services = lib.mkIf (config.my.services.container-updater.enable or false) {
      # Wait for cache availability before running container updates
      "service-container-updater" = {
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];
      };
    };
  };
}
