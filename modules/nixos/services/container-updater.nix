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
      # ----------------------------------------------------------------
      # Stage: fetch/build the new closure, register as profile, swap
      # symlink. The running container is NOT touched — it keeps serving
      # the old closure until activated. Safe to run on attic itself
      # without disrupting other containers' substituter access.
      # ----------------------------------------------------------------
      services."update-container-stage@" = {
        description = "Stage update for NixOS Container %i (no restart)";
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
          echo "Staging update for container: $CONTAINER"

          TARGET="${cfg.flakeURI}#nixosConfigurations.container-factory.config.containers.$CONTAINER.path"

          echo "Building/Fetching $TARGET..."
          STORE_PATH=$(nix build --print-out-paths --no-link --accept-flake-config "$TARGET")

          if [ -z "$STORE_PATH" ]; then
            echo "Failed to build or fetch $TARGET"
            exit 1
          fi

          echo "Registering $CONTAINER as a Nix profile (GC safe)..."
          nix-env --profile "/nix/var/nix/profiles/containers/$CONTAINER" --set "$STORE_PATH"

          # Defensive: /var/lib/machines/<name>/ is normally created by the NixOS
          # containers module when my.containers.<name>.enable = true on this host.
          # Create it ourselves if missing so a one-off update for a never-deployed
          # container doesn't fail at the symlink swap.
          mkdir -p "/var/lib/machines/$CONTAINER"

          echo "Updating symlink /var/lib/machines/$CONTAINER/current..."
          ln -sfn "/nix/var/nix/profiles/containers/$CONTAINER" "/var/lib/machines/$CONTAINER/current"

          echo "Stage complete for $CONTAINER. Activate with:"
          echo "  systemctl start update-container-activate@$CONTAINER.service"
        '';

        serviceConfig = {
          Type = "oneshot";
          TimeoutStartSec = "15m";
        };
      };

      # ----------------------------------------------------------------
      # Activate: restart the container so it picks up the staged closure.
      # ~5-30s downtime per container. Must be run AFTER stage.
      # ----------------------------------------------------------------
      services."update-container-activate@" = {
        description = "Activate staged update for NixOS Container %i (restart)";

        path = with pkgs; [ systemd ];

        scriptArgs = "%i";
        script = ''
          CONTAINER=$1
          if machinectl status "$CONTAINER" >/dev/null 2>&1; then
            echo "Restarting container $CONTAINER to apply staged update..."
            machinectl restart "$CONTAINER"
          else
            echo "Container $CONTAINER is not currently running. Starting it..."
            systemctl start "container@$CONTAINER"
          fi
          echo "Activation complete for $CONTAINER."
        '';

        serviceConfig = {
          Type = "oneshot";
          TimeoutStartSec = "5m";
        };
      };

      # ----------------------------------------------------------------
      # Combined stage + activate (backward-compatible entry point).
      # Equivalent to the original update-container@ behaviour: build,
      # swap, restart, all in one shot.
      # ----------------------------------------------------------------
      services."update-container@" = {
        description = "Update NixOS Container %i (stage + activate)";

        path = with pkgs; [ systemd ];

        scriptArgs = "%i";
        script = ''
          CONTAINER=$1
          systemctl start --wait "update-container-stage@$CONTAINER.service"
          systemctl start --wait "update-container-activate@$CONTAINER.service"
        '';

        serviceConfig = {
          Type = "oneshot";
          TimeoutStartSec = "20m";
        };
      };

      # ----------------------------------------------------------------
      # Bulk orchestrator: three-phase update of every registered
      # container, designed to avoid the attic-eats-itself bootstrap
      # window. Stage everything in parallel (no restarts → attic keeps
      # serving). Then activate non-attic in parallel. Then attic last.
      # ----------------------------------------------------------------
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
        description = "Smart bulk update of standalone NixOS containers (stage all → activate non-attic → activate attic last)";

        path = with pkgs; [ systemd ];

        serviceConfig = {
          Type = "oneshot";
          TimeoutStartSec = "1h";
        };

        script = ''
          set -e
          CONTAINERS="${lib.concatStringsSep " " cfg.containers}"

          echo "=== Phase 1: staging updates for all containers in parallel ==="
          for c in $CONTAINERS; do
            echo "  staging $c..."
            systemctl start --wait "update-container-stage@$c.service" &
          done
          wait
          echo "All stages complete."

          echo "=== Phase 2: activating non-attic containers in parallel ==="
          for c in $CONTAINERS; do
            if [ "$c" != "attic" ]; then
              echo "  activating $c..."
              systemctl start --wait "update-container-activate@$c.service" &
            fi
          done
          wait
          echo "Non-attic activations complete."

          if echo " $CONTAINERS " | grep -q " attic "; then
            echo "=== Phase 3: activating attic last ==="
            systemctl start --wait "update-container-activate@attic.service"
          fi

          echo "Bulk update complete."
        '';
      };

      # Ensure the profiles directory exists
      tmpfiles.rules = [
        "d /nix/var/nix/profiles/containers 0755 root root - -"
      ];
    };
  };
}
