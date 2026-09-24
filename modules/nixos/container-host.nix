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
      description = ''
        Containers still built by container-factory and pulled/cached from the
        CI manifest, but excluded from the automatic nightly bulk update —
        e.g. a reverse proxy you don't want unattended-restarted. Still
        stageable/updatable any time via
        `systemctl start update-container@<name>`.
      '';
      example = [
        "attic"
        "caddy"
        "crowdsec"
      ];
    };

    excludeFromStandalone = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = ''
        Containers that must build embedded on this host and never be
        treated as standalone/pulled at all — for a container-factory
        structural conflict (e.g. an attrsOf option that recurses in the
        factory's eval), not merely "don't auto-restart" (use
        excludeFromUpdater for that).
      '';
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
      manifestUrl = "https://github.com/kleinbem/nix-config/releases/download/container-manifest/manifest.json";
      # Source from config.containers (the real nspawn instance names mkContainer
      # produces), not config.my.containers (the my.containers.<option-name>
      # keys) — a preset's mkContainer `name` can differ from its option name
      # (e.g. `my.containers.dashboard` → container "dashboard-homepage"), and
      # this list is matched against the real name by isStandalone in
      # nix-presets/lib/factory.nix. Deriving from the option-name set instead
      # silently left any such container permanently embedded, never pulled.
      #
      # excludeFromStandalone subtracts here, at the base list, because
      # isStandalone matches against this exact list — a container that
      # genuinely can't be factory-built (persona-runtime's attrsOf
      # structural conflict) must never appear in it, or NixOS expects a
      # manifest entry that will never exist. excludeFromUpdater does NOT
      # subtract here — it only opts a container out of the *nightly* bulk
      # restart (below); removing it from this base list would silently
      # build it embedded again instead of pulled/cached.
      containers = lib.subtractLists cfg.excludeFromStandalone (lib.attrNames config.containers);
      excludeFromNightly = cfg.excludeFromUpdater;
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
                  lib.optional ((container.hostDataDir or null) != null) container.hostDataDir
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
