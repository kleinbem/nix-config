{ pkgs, ... }:

{
  # ==========================================
  # SYSTEM SCRIPTS & OVERLAYS
  # ==========================================
  # We use overlays to ensure custom scripts are part of the 'pkgs' set,
  # making them referenceable across all NixOS modules.
  nixpkgs.overlays = [
    (final: _: {
      verify-system = final.writeShellApplication {
        name = "verify-system";
        runtimeInputs = with final; [
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

      smart-switch = final.writeShellApplication {
        name = "smart-switch";
        runtimeInputs = with final; [
          coreutils
          gnugrep
          nh
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

          TARGET="''${1:-.}"
          FLAKE_PATH=$(readlink -f "$TARGET")
          DRY_OUTPUT=$(nixos-rebuild dry-build --flake "$FLAKE_PATH" 2>&1 || true)

          if echo "$DRY_OUTPUT" | grep -q "will be built:"; then
              REAL_COUNT=$(echo "$DRY_OUTPUT" | grep -c ".*\.drv")
          else
              REAL_COUNT=0
          fi

          if [ "''${REAL_COUNT}" -gt "''${THRESHOLD}" ]; then
              echo -e "''${COLOR_RED}🛑 STOP! Massive build detected.''${COLOR_RESET}"
              echo -e "This update requires building ''${COLOR_YELLOW}''${REAL_COUNT}''${COLOR_RESET} packages from source."
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

          echo -e "''${COLOR_GREEN}🚀 Proceeding with switch to ''${FLAKE_PATH}...''${COLOR_RESET}"
          unset FLAKE
          nh os switch "$FLAKE_PATH"
        '';
      };

      nix-security-audit = final.writeShellApplication {
        name = "nix-security-audit";
        runtimeInputs = with final; [
          coreutils
          gnugrep
          vulnix
          trivy
          gitleaks
          lynis
          systemd
          curl
          jq
          podman
        ];
        text = ''
          # Inject whitelists paths as environment variables
          export VULNIX_WHITELIST="${./vulnix.whitelist.yaml}"
          export TRIVY_IGNORE="${./.trivyignore}"
          ${builtins.readFile ./files/nix-security-audit.sh}
        '';
      };
    })
  ];

  environment.systemPackages = with pkgs; [
    verify-system
    smart-switch
    nix-security-audit
  ];
}
