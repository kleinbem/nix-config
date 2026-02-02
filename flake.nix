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

    nixpak = {
      url = "github:nixpak/nixpak";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Secret Management
    sops-nix.url = "github:Mic92/sops-nix";
    sops-nix.inputs.nixpkgs.follows = "nixpkgs";

    # Private Secrets (GitHub Repo)
    nix-secrets = {
      url = "git+ssh://git@github.com/kleinbem/nix-secrets.git?ref=main";
      flake = false;
    };

    # Local Workspace (Absolute paths for local dev without pushing)
    nix-hardware.url = "git+file:///home/martin/Develop/github.com/kleinbem/nix/nix-hardware";
    nix-devshells.url = "git+file:///home/martin/Develop/github.com/kleinbem/nix/nix-devshells";
    nix-presets.url = "git+file:///home/martin/Develop/github.com/kleinbem/nix/nix-presets";
    nix-packages.url = "git+file:///home/martin/Develop/github.com/kleinbem/nix/nix-packages";

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
  };

  outputs =
    inputs@{
      self,
      nixpkgs,
      treefmt-nix,
      pre-commit-hooks,
      flake-parts,
      ...
    }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [
        ./modules/flake/images.nix
      ];
      systems = [ "x86_64-linux" ];

      perSystem =
        {
          pkgs,
          system,
          ...
        }:
        let
          # Treefmt Configuration
          treefmtEval = treefmt-nix.lib.evalModule pkgs {
            projectRootFile = "flake.nix";
            programs.nixfmt.enable = true;
            programs.nixfmt.package = pkgs.nixfmt;
          };
        in
        {
          # ---------------------------------------------------------
          # 1. The Agentic Development Shell
          # ---------------------------------------------------------
          formatter = treefmtEval.config.build.wrapper;

          devShells.default = inputs.nix-devshells.devShells.${system}.default;

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

          # ---------------------------------------------------------
          # 4. Image Generation (Moved to PerSystem)
          # ---------------------------------------------------------
        };

      flake = {
        nixosConfigurations = {
          nixos-nvme = nixpkgs.lib.nixosSystem {
            system = "x86_64-linux";
            specialArgs = { inherit inputs self; };
            modules = [ ./hosts/nixos-nvme/default.nix ];
          };
        };
      };
    };
}
