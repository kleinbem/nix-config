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

      # Gated to x86 only: the override creates a unique derivation hash, so
      # aarch64 misses the cache and forces source compilation of the devenv
      # Rust dependency chain (aws-lc-sys etc.) — either OOMs or hits a known
      # aarch64 build bug. Our ARM hosts (orin-nano, core-pi, …) are servers
      # without dev shells anyway, so the loss is purely cosmetic.
      devShells = lib.optionalAttrs (system == "x86_64-linux") {
        default = inputs.nix-devshells.devShells.${system}.default.overrideAttrs (old: {
          shellHook = ''
            ${old.shellHook or ""}
            ${config.checks.pre-commit-check.shellHook}
          '';
        });
      };

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
            name: host:
            !(lib.hasPrefix "container-factory" name) && host.pkgs.stdenv.hostPlatform.system == system
          ) self.nixosConfigurations;

          # Create a check derivation for each matching host
          hostChecks = lib.mapAttrs' (
            name: host: lib.nameValuePair "host-${name}" host.config.system.build.toplevel
          ) systemHosts;

          # NO host-phone check: nix-on-droid can never be evaluated purely —
          # upstream pins its cross-compiled proot-static as a context-free
          # /nix/store string, which types.package coerces via
          # builtins.storePath (rejected in pure eval; --impure additionally
          # needs nix-on-droid.cachix.org to substitute the path). It builds
          # on-device only (nix-on-droid switch runs --impure by design), so a
          # checks entry just breaks `nix flake check` for every consumer.
          # The config stays exposed as nixOnDroidConfigurations.phone.

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

          # Reproducibility guard: the committed flake.lock must pin every input
          # to a fetchable source (github:, …), never a local file:///home path.
          # Those creep in when local `nix` evals dirty the lock (the OVERRIDES
          # dev flow) and someone commits it, or when sibling `inputs.follows`
          # get stripped from flake.nix and a re-lock resolves siblings
          # independently. Unlike a pre-commit hook scoped to `flake.lock$` (which
          # only fires when the lock is in the changeset), this is a flake check —
          # build-all builds it on EVERY PR, so committed drift can never sneak in
          # via a PR that doesn't happen to touch the lock.
          flake-lock-no-file-url =
            inputs.nixpkgs.legacyPackages.${system}.runCommand "flake-lock-no-file-url" { }
              ''
                if grep -n 'file://' ${../../flake.lock}; then
                  echo "ERROR: flake.lock pins local file:// inputs (lines above) — non-reproducible." >&2
                  echo "Fix: re-resolve the sibling to github (nix flake update <sib>, same rev) and" >&2
                  echo "restore its inputs.<sib>.follows dedup in flake.nix, then re-lock." >&2
                  exit 1
                fi
                touch "$out"
              '';

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
        // specChecks;
    };
}
