{
  description = "AI-Augmented NixOS with COSMIC and Nixpak";

  inputs = {
    # --- Core ---
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixpkgs-stable.url = "github:NixOS/nixpkgs/nixos-25.11";

    flake-parts.url = "github:hercules-ci/flake-parts";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    devenv = {
      url = "github:cachix/devenv";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixpak = {
      url = "github:nixpak/nixpak";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    impermanence.url = "github:nix-community/impermanence";

    # Secret Management
    sops-nix.url = "github:Mic92/sops-nix";
    sops-nix.inputs.nixpkgs.follows = "nixpkgs";

    # Private Secrets (GitHub Repo)
    nix-secrets = {
      url = "path:/home/martin/Develop/github.com/kleinbem/nix/nix-secrets";
      flake = false;
    };

    # Modules & Configurations (Pulled from local submodules for speed)
    nix-hardware = {
      url = "path:/home/martin/Develop/github.com/kleinbem/nix/nix-hardware";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-devshells = {
      url = "path:/home/martin/Develop/github.com/kleinbem/nix/nix-devshells";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-presets = {
      url = "path:/home/martin/Develop/github.com/kleinbem/nix/nix-presets";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-packages = {
      url = "path:/home/martin/Develop/github.com/kleinbem/nix/nix-packages";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-templates = {
      url = "path:/home/martin/Develop/github.com/kleinbem/nix/nix-templates";
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

    # Multi-host Deployment
    colmena = {
      url = "github:zhaofengli/colmena";
      inputs.nixpkgs.follows = "nixpkgs";
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
      ];
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];

      perSystem =
        {
          config,
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
          # 2. Checks (Pre-commit)
          # ---------------------------------------------------------
          checks.pre-commit-check = pre-commit-hooks.lib.${system}.run {
            src = ./.;
            hooks = {
              nixfmt.enable = true;
              statix.enable = true;
              deadnix.enable = true;
            };
          };

          checks.code-server-test = import ./tests/code-server.nix {
            pkgs = inputs.nixpkgs.legacyPackages.${system};
            inherit inputs;
          };
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
              inherit system;
              specialArgs = {
                inherit inputs self myInventory;
              };
              inherit modules;
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
            # orin-nano = mkHost "orin-nano" {
            #   modules = [ ./hosts/orin-nano/default.nix ];
            # };
            rpi5-1 = mkHost "rpi5-1" {
              modules = [ ./hosts/rpi5-1/default.nix ];
            };
            rpi5-2 = mkHost "rpi5-2" {
              modules = [ ./hosts/rpi5-2/default.nix ];
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
                nixpkgs = import inputs.nixpkgs { system = "x86_64-linux"; };
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
                nixpkgs.system = hostMeta.nixos-nvme.system;
              };

              # OpenWrt routers (NixOS in LXC)
              router-1 = {
                deployment = {
                  targetHost = hostMeta.router-1.ip;
                  targetUser = "root";
                  inherit (hostMeta.router-1) tags;
                };
                imports = [ ./hosts/router-1/default.nix ];
                nixpkgs.system = hostMeta.router-1.system;
              };
              router-2 = {
                deployment = {
                  targetHost = hostMeta.router-2.ip;
                  targetUser = "root";
                  inherit (hostMeta.router-2) tags;
                };
                imports = [ ./hosts/router-2/default.nix ];
                nixpkgs.system = hostMeta.router-2.system;
              };

              # NVIDIA Jetson Orin Nano
              orin-nano = {
                deployment = {
                  targetHost = hostMeta.orin-nano.ip;
                  targetUser = "root";
                  inherit (hostMeta.orin-nano) tags;
                };
                imports = [ ./hosts/orin-nano/default.nix ];
                nixpkgs.system = hostMeta.orin-nano.system;
              };

              # Raspberry Pi 5 nodes
              rpi5-1 = {
                deployment = {
                  targetHost = hostMeta.rpi5-1.ip;
                  targetUser = "root";
                  inherit (hostMeta.rpi5-1) tags;
                };
                imports = [ ./hosts/rpi5-1/default.nix ];
                nixpkgs.system = hostMeta.rpi5-1.system;
              };
              rpi5-2 = {
                deployment = {
                  targetHost = hostMeta.rpi5-2.ip;
                  targetUser = "root";
                  inherit (hostMeta.rpi5-2) tags;
                };
                imports = [ ./hosts/rpi5-2/default.nix ];
                nixpkgs.system = hostMeta.rpi5-2.system;
              };
            };
        };
    };
}
