{
  description = "AI-Augmented NixOS with COSMIC and Firejail";

  inputs = {
    # --- Core ---
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixpkgs-stable.url = "github:NixOS/nixpkgs/nixos-25.11";
    nixpkgs-master.url = "github:NixOS/nixpkgs/master";

    flake-parts.url = "github:hercules-ci/flake-parts";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    devenv = {
      # FIXME: Temporary pin to bypass broken libghostty-vt requirement in devenv 2.1
      url = "github:cachix/devenv/070577452d0c81d62168ef8b158ee4317ace7e21";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.ghostty.follows = "ghostty";
    };

    ghostty = {
      url = "github:mitchellh/ghostty";
    };

    impermanence.url = "github:nix-community/impermanence";

    # Secret Management
    sops-nix.url = "github:Mic92/sops-nix";
    sops-nix.inputs.nixpkgs.follows = "nixpkgs";

    # Private Secrets (GitHub Repo)
    nix-secrets = {
      url = "github:kleinbem/nix-secrets";
      flake = false;
    };

    # Modules & Configurations (Pulled from local submodules for speed)
    nix-hardware = {
      url = "github:kleinbem/nix-hardware";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.jetpack-nixos.follows = "jetpack-nixos";
    };
    nix-devshells = {
      url = "github:kleinbem/nix-devshells";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-presets = {
      url = "git+file:///home/martin/Develop/github.com/kleinbem/nix/nix-presets";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-packages = {
      url = "github:kleinbem/nix-packages";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-templates = {
      url = "github:kleinbem/nix-templates";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    pre-commit-hooks = {
      url = "github:cachix/pre-commit-hooks.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Nix User Repository
    nur = {
      url = "github:nix-community/NUR";
    };

    # Image Generation
    nixos-generators = {
      url = "github:nix-community/nixos-generators";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    lanzaboote = {
      url = "github:nix-community/lanzaboote";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixvim = {
      url = "github:nix-community/nixvim";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-vscode-extensions = {
      url = "github:nix-community/nix-vscode-extensions";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    antigravity-nix = {
      url = "github:jacopone/antigravity-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    jetpack-nixos = {
      url = "github:anduril/jetpack-nixos";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # cosmic flake removed — using nixpkgs COSMIC instead (more reliable, pre-built by Hydra)

    # Multi-host Deployment
    # colmena flake removed — using nixpkgs instead

    nix-topology = {
      url = "github:oddlama/nix-topology";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-mineral = {
      url = "github:cynicsketch/nix-mineral";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    chaotic.url = "github:chaotic-cx/nyx/nyxpkgs-unstable";

    nix-on-droid = {
      url = "github:nix-community/nix-on-droid/release-24.05";
      # NOTE: Do NOT follow nixpkgs here. nix-on-droid needs its own pinned
      # nixpkgs with an older glibc to avoid the TCGETS2 proot-termux bug.
      # See: https://github.com/nix-community/nix-on-droid/issues/495
      inputs.home-manager.follows = "home-manager";
    };

  };

  outputs =
    inputs@{
      self,
      pre-commit-hooks,
      flake-parts,
      ...
    }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [
        ./modules/flake/images.nix
        inputs.nix-topology.flakeModule
      ];
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];

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
            ./topology.nix
            { inherit (self) nixosConfigurations; }
          ];

          # ---------------------------------------------------------
          # 4. Checks & Verifications
          # ---------------------------------------------------------
          checks =
            let
              # Filter hosts that match the current system
              systemHosts = lib.filterAttrs (
                _: host: host.pkgs.stdenv.hostPlatform.system == system
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
                host-nixos-nvme-hardened =
                  self.nixosConfigurations.nixos-nvme.config.specialisation.hardened.configuration.system.build.toplevel;
              };
            in
            {
              pre-commit-check = pre-commit-hooks.lib.${system}.run {
                src = ./.;
                hooks = {
                  nixfmt.enable = true;
                  statix.enable = true;
                  deadnix.enable = true;
                };
              };

              code-server-test = import ./tests/code-server.nix {
                pkgs = inputs.nixpkgs.legacyPackages.${system};
                inherit inputs;
              };

              caddy-test = import ./tests/caddy.nix {
                pkgs = inputs.nixpkgs.legacyPackages.${system};
                inherit inputs;
              };

              mobile-link-test = import ./tests/mobile-link.nix {
                pkgs = inputs.nixpkgs.legacyPackages.${system};
                inherit inputs self;
              };

              recovery-test = import ./tests/recovery.nix {
                pkgs = inputs.nixpkgs.legacyPackages.${system};
                inherit inputs;
              };

              # Verify that the infrastructure topology can be rendered
              # topology-check = config.topology.config.build.svg;
            }
            // hostChecks
            // droidChecks
            // specChecks;
        };

      flake =
        let
          myInventory = import ./inventory.nix;

          # Helper to create a nixosSystem for any host
          mkHost =
            name:
            {
              system ? myInventory.hosts.${name}.system,
              modules,
            }:
            inputs.nixpkgs.lib.nixosSystem {
              specialArgs = {
                inherit inputs self myInventory;
              };
              modules = [
                {
                  nixpkgs = {
                    hostPlatform = system;
                    config = {
                      allowUnfree = true;
                      allowUnfreePredicate = _: true;
                    };
                  };
                }
                inputs.nix-topology.nixosModules.default
              ]
              ++ (if builtins.isList modules then modules else [ modules ]);
            };
        in
        {
          nixosConfigurations = {
            nixos-nvme = mkHost "nixos-nvme" {
              modules = [ ./hosts/nixos-nvme/default.nix ];
            };
            router-1 = mkHost "router-1" {
              modules = [ ./hosts/router-1/default.nix ];
            };
            router-2 = mkHost "router-2" {
              modules = [ ./hosts/router-2/default.nix ];
            };
            orin-nano = mkHost "orin-nano" {
              modules = [ ./hosts/orin-nano/default.nix ];
            };
            core-pi = mkHost "core-pi" {
              modules = [ ./hosts/core-pi/default.nix ];
            };
            hass-pi = mkHost "hass-pi" {
              modules = [ ./hosts/hass-pi/default.nix ];
            };
            nasbook = mkHost "nasbook" {
              modules = [ ./hosts/nasbook/default.nix ];
            };
          };

          nixOnDroidConfigurations = {
            phone = inputs.nix-on-droid.lib.nixOnDroidConfiguration {
              pkgs = import inputs.nixpkgs {
                system = "aarch64-linux";
                config = {
                  allowUnfree = true;
                  permittedInsecurePackages = [
                    "olivetin-2025.11.25"
                  ];
                };
                overlays = [ inputs.nix-on-droid.overlays.default ];
              };
              extraSpecialArgs = { inherit inputs self myInventory; };
              modules = [ ./hosts/phone/default.nix ];
            };
          };

          diskoConfigurations = {
            inherit (self.nixosConfigurations.nixos-nvme.config) disko;
          };

          # ─── Colmena Deployment ────────────────────────────────
          colmena =
            let
              hostMeta = myInventory.hosts;
            in
            {
              meta = {
                nixpkgs = import inputs.nixpkgs { hostPlatform = "x86_64-linux"; };
                specialArgs = {
                  inherit inputs self myInventory;
                };
              };

              # Main workstation (deploy locally)
              nixos-nvme = {
                deployment = {
                  allowLocalDeployment = true;
                  targetHost = null; # Local deployment
                };
                imports = [ ./hosts/nixos-nvme/default.nix ];
                nixpkgs.hostPlatform = hostMeta.nixos-nvme.system;
              };

              # OpenWrt routers (NixOS in LXC)
              router-1 = {
                deployment = {
                  targetHost = hostMeta.router-1.ip;
                  targetUser = "root";
                  inherit (hostMeta.router-1) tags;
                };
                imports = [ ./hosts/router-1/default.nix ];
                nixpkgs.hostPlatform = hostMeta.router-1.system;
              };
              router-2 = {
                deployment = {
                  targetHost = hostMeta.router-2.ip;
                  targetUser = "root";
                  inherit (hostMeta.router-2) tags;
                };
                imports = [ ./hosts/router-2/default.nix ];
                nixpkgs.hostPlatform = hostMeta.router-2.system;
              };

              # NVIDIA Jetson Orin Nano
              orin-nano = {
                deployment = {
                  targetHost = hostMeta.orin-nano.ip;
                  targetUser = "root";
                  inherit (hostMeta.orin-nano) tags;
                };
                imports = [ ./hosts/orin-nano/default.nix ];
                nixpkgs.hostPlatform = hostMeta.orin-nano.system;
              };

              # Raspberry Pi 5 nodes
              core-pi = {
                deployment = {
                  targetHost = hostMeta.core-pi.ip;
                  targetUser = "root";
                  inherit (hostMeta.core-pi) tags;
                };
                imports = [ ./hosts/core-pi/default.nix ];
                nixpkgs.hostPlatform = hostMeta.core-pi.system;
              };
              hass-pi = {
                deployment = {
                  targetHost = hostMeta.hass-pi.ip;
                  targetUser = "root";
                  inherit (hostMeta.hass-pi) tags;
                };
                imports = [ ./hosts/hass-pi/default.nix ];
                nixpkgs.hostPlatform = hostMeta.hass-pi.system;
              };
              nasbook = {
                deployment = {
                  targetHost = hostMeta.nasbook.ip;
                  targetUser = "root";
                  inherit (hostMeta.nasbook) tags;
                };
                imports = [ ./hosts/nasbook/default.nix ];
                nixpkgs.hostPlatform = hostMeta.nasbook.system;
              };
            };
        };
    };
}
