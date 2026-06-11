{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.my.services.container-updater;
in
{
  options.my.services.container-updater = {
    enable = lib.mkEnableOption "Automated container closures updater via Nix Profiles";
    flakeURI = lib.mkOption {
      type = lib.types.str;
      default = "github:kleinbem/nix";
      description = "The flake URI to pull container configurations from.";
    };
    containers = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "List of standalone containers to auto-update.";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd = {
      # Systemd service template for updating a specific container
      services."update-container@" = {
        description = "Update Standalone NixOS Container %i";
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];

        path = with pkgs; [
          nix
          systemd
          git
          jq
        ];

        scriptArgs = "%i";
        script = ''
          CONTAINER=$1
          echo "Starting update for container: $CONTAINER"

          # Pull the closure from the factory
          TARGET="${cfg.flakeURI}#nixosConfigurations.container-factory.config.containers.$CONTAINER.path"

          echo "Building/Fetching $TARGET..."
          # --accept-flake-config to allow using binary caches automatically if defined
          STORE_PATH=$(nix build --print-out-paths --no-link --accept-flake-config "$TARGET")

          if [ -z "$STORE_PATH" ]; then
            echo "Failed to build or fetch $TARGET"
            exit 1
          fi

          echo "Registering $CONTAINER as a Nix profile (GC safe)..."
          nix-env --profile "/nix/var/nix/profiles/containers/$CONTAINER" --set "$STORE_PATH"

          echo "Updating symlink /var/lib/machines/$CONTAINER/current..."
          ln -sfn "/nix/var/nix/profiles/containers/$CONTAINER" "/var/lib/machines/$CONTAINER/current"

          if machinectl status "$CONTAINER" >/dev/null 2>&1; then
            echo "Restarting container $CONTAINER to apply updates..."
            machinectl restart "$CONTAINER"
          else
            echo "Container $CONTAINER is not currently running. Will use new profile on next start."
          fi

          echo "Update for $CONTAINER completed successfully."
        '';

        serviceConfig = {
          Type = "oneshot";
          TimeoutStartSec = "15m"; # In case it has to build from source
        };
      };

      # Systemd timer to update all registered containers nightly
      timers."update-containers" = lib.mkIf (cfg.containers != [ ]) {
        description = "Nightly update of standalone NixOS containers";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = "*-*-* 03:00:00";
          Persistent = true;
          RandomizedDelaySec = "30m";
        };
      };

      services."update-containers" = lib.mkIf (cfg.containers != [ ]) {
        description = "Trigger updates for all standalone NixOS containers";
        serviceConfig = {
          Type = "oneshot";
        };
        script = ''
          for container in ${lib.concatStringsSep " " cfg.containers}; do
            echo "Triggering update for $container..."
            ${pkgs.systemd}/bin/systemctl start update-container@$container.service
          done
        '';
      };

      # Ensure the profiles directory exists
      tmpfiles.rules = [
        "d /nix/var/nix/profiles/containers 0755 root root - -"
      ];
    };
  };
}
