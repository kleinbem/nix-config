{ inputs, self, ... }:
{
  perSystem =
    {
      config,
      lib,
      system,
      ...
    }:
    {
      # ---------------------------------------------------------
      # 1. The Agentic Development Shell
      # ---------------------------------------------------------
      formatter = inputs.nix-devshells.formatter.${system};

      devShells.default = inputs.nix-devshells.devShells.${system}.default.overrideAttrs (old: {
        shellHook = ''
          ${old.shellHook or ""}
          ${config.checks.pre-commit-check.shellHook}
        '';
      });

      # ---------------------------------------------------------
      # 3. Topology (Auto-generated network diagrams)
      # ---------------------------------------------------------
      topology.modules = [
        ../../topology.nix
        { inherit (self) nixosConfigurations; }
      ];

      # ---------------------------------------------------------
      # 4. Checks & Verifications
      # ---------------------------------------------------------
      checks =
        let
          # Filter hosts that match the current system (excluding non-bootable helpers)
          systemHosts = lib.filterAttrs (
            name: host: name != "container-factory" && host.pkgs.stdenv.hostPlatform.system == system
          ) self.nixosConfigurations;

          # Create a check derivation for each matching host
          hostChecks = lib.mapAttrs' (
            name: host: lib.nameValuePair "host-${name}" host.config.system.build.toplevel
          ) systemHosts;

          # Add Nix-on-Droid check if it matches the current system
          droidChecks = lib.optionalAttrs (system == "aarch64-linux") {
            host-phone = self.nixOnDroidConfigurations.phone.activationPackage;
          };

          # Specialisation Checks (for complex hosts)
          specChecks = lib.optionalAttrs (system == "x86_64-linux" && (systemHosts ? "nixos-nvme")) {
            host-nixos-nvme-playground =
              self.nixosConfigurations.nixos-nvme.config.specialisation.playground.configuration.system.build.toplevel;
          };
        in
        {
          pre-commit-check = inputs.git-hooks.lib.${system}.run {
            src = ../../.;
            hooks = {
              nixfmt.enable = true;
              statix.enable = true;
              deadnix.enable = true;
            };
          };

          code-server-test = import ../../tests/code-server.nix {
            pkgs = inputs.nixpkgs.legacyPackages.${system};
            inherit inputs;
          };

          caddy-test = import ../../tests/caddy.nix {
            pkgs = inputs.nixpkgs.legacyPackages.${system};
            inherit inputs;
          };

          mobile-link-test = import ../../tests/mobile-link.nix {
            pkgs = inputs.nixpkgs.legacyPackages.${system};
            inherit inputs self;
          };

          recovery-test = import ../../tests/recovery.nix {
            pkgs = inputs.nixpkgs.legacyPackages.${system};
            inherit inputs;
          };
        }
        // hostChecks
        // droidChecks
        // specChecks;
    };
}
