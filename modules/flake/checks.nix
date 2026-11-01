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

      # x86 only: the override misses the cache, and on aarch64 that means
      # building devenv's Rust chain from source. ARM hosts have no dev shells.
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

          # No host-phone check: nix-on-droid pins proot-static as a bare store
          # path, which pure eval rejects. It builds on-device only
          # (nixOnDroidConfigurations.phone).

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

          # flake.lock must never pin a local file:// input; local OVERRIDES
          # evals dirty the lock. A flake check rather than a pre-commit hook,
          # so it runs on every PR, not only ones touching the lock.
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

          # Packages from our open nixpkgs PRs (nix-packages' nixpkgs-prs.json)
          # that hosts install, built from each host's own pkgs, so a breaking
          # update stops in its PR and the builds reach Attic before promote.
          # orin-nano is left out: CI never builds its jetpack closure.
          nixpkgs-prs =
            let
              registry = lib.importJSON "${inputs.nix-packages}/nixpkgs-prs.json";
              entries = lib.attrValues registry;
              prAttrs = lib.concatMap (entry: entry.attrs) entries;
              prServices = lib.concatMap (entry: lib.attrNames (entry.modules or { })) entries;

              installed =
                host:
                let
                  inherit (host) config pkgs;
                  outPaths =
                    map (p: p.outPath or "") config.environment.systemPackages
                    ++ lib.concatMap (
                      name: lib.optional (config.services.${name}.enable or false) config.services.${name}.package.outPath
                    ) prServices;
                in
                # tryEval: a package no host installs may not even evaluate
                # with the fleet's nixpkgs; the hosts that install one fail
                # their own eval in that case.
                lib.filter (
                  attr:
                  let
                    outPath = builtins.tryEval (pkgs.${attr}.outPath or "");
                  in
                  outPath.success && lib.elem outPath.value outPaths
                ) prAttrs;

              builtHosts = lib.filterAttrs (name: _: name != "orin-nano") systemHosts;
            in
            inputs.nixpkgs.legacyPackages.${system}.linkFarm "nixpkgs-prs" (
              lib.concatLists (
                lib.mapAttrsToList (
                  hostName: host:
                  map (attr: {
                    name = "${hostName}-${attr}";
                    path = host.pkgs.${attr};
                  }) (installed host)
                ) builtHosts
              )
            );

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
        // hostChecks;
    };
}
