{ pkgs, ... }:

let
  verify-system = pkgs.writeShellApplication {
    name = "verify-system";
    runtimeInputs = with pkgs; [
      coreutils
      systemd
      curl
      pciutils
      gnugrep
      fzf
      fastfetch
      mpv
      ripgrep
      starship
      podman
      nixfmt
      deadnix
      statix
    ];
    text = builtins.readFile ./files/verify-system.sh;
  };
  smart-switch = pkgs.writeShellApplication {
    name = "smart-switch";
    runtimeInputs = with pkgs; [
      coreutils
      gnugrep
      nh
      # nixos-rebuild is usually available in system path, but good to be explicit if possible.
      # However, nixos-rebuild depends on the system's nix config so we often rely on path.
    ];
    text = ''
      #!/usr/bin/env bash
      set -e

      # Configuration
      THRESHOLD=15
      COLOR_RED='\033[0;31m'
      COLOR_GREEN='\033[0;32m'
      COLOR_YELLOW='\033[1;33m'
      COLOR_RESET='\033[0m'

      echo -e "''${COLOR_YELLOW}🤖 Smart Switch: Checking build requirements...''${COLOR_RESET}"

      # Run dry run and capture output
      # We use 'nix build' dry run effectively via nh's underlying mechanism or just nixos-rebuild --dry-run
      TARGET="''${1:-.}"
      FLAKE_PATH=$(readlink -f "$TARGET")

      # "will be built" detection
      DRY_OUTPUT=$(nixos-rebuild dry-build --flake "$FLAKE_PATH" 2>&1 || true)

      # Count how many paths need building
      # BUILD_COUNT=$(echo "$DRY_OUTPUT" | grep -c "will be built:") || true

      if echo "$DRY_OUTPUT" | grep -q "will be built:"; then
          # A safe heuristic for "massive" is just raw line count of unique derivations.
          REAL_COUNT=$(echo "$DRY_OUTPUT" | grep -c ".*\.drv")
      else
          REAL_COUNT=0
      fi

      if [ "''${REAL_COUNT}" -gt "''${THRESHOLD}" ]; then
          echo -e "''${COLOR_RED}🛑 STOP! Massive build detected.''${COLOR_RESET}"
          echo -e "This update requires building ''${COLOR_YELLOW}''${REAL_COUNT}''${COLOR_RESET} packages from source."
          echo -e "Threshold is set to ''${THRESHOLD}."
          echo ""
          echo "This usually means the binary cache is not ready yet."
          echo "Recommendation: Wait 6-12 hours and try again."
          echo ""
          read -p "Force update anyway? (y/N) " -n 1 -r
          echo
          if [[ ! $REPLY =~ ^[Yy]$ ]]; then
              echo "Aborting."
              exit 1
          fi
      else
          echo -e "''${COLOR_GREEN}✅ Cache looks good! (''${REAL_COUNT} builds)''${COLOR_RESET}"
      fi

      # Proceed with actual switch
      echo -e "''${COLOR_GREEN}🚀 Proceeding with switch to ''${FLAKE_PATH}...''${COLOR_RESET}"
      # Unset FLAKE to force nh to use the argument we pass
      unset FLAKE
      nh os switch "$FLAKE_PATH"
    '';
  };
in
{
  environment.systemPackages = [
    verify-system
    smart-switch
  ];
}
