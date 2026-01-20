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
  };

  outputs =
    inputs@{
      self,
      nixpkgs,
      treefmt-nix,
      pre-commit-hooks,
      nixos-generators,
      flake-parts,
      ...
    }:
    flake-parts.lib.mkFlake { inherit inputs; } {
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

          devShells.default = pkgs.mkShell {
            buildInputs = [
              pkgs.aider-chat
              pkgs.statix
              pkgs.nixfmt
              pkgs.deadnix
              pkgs.nil
              pkgs.sops
              pkgs.age
              pkgs.age-plugin-yubikey
              nixos-generators.packages.${system}.nixos-generate
            ];

            shellHook = ''
              ${self.checks.${system}.pre-commit-check.shellHook}
              echo "🤖 Spec-Driven NixOS Environment Loaded"
              echo "   - System: NixOS + COSMIC + Nixpak"

              if [ -z "$GEMINI_API_KEY" ] && [ -z "$OLLAMA_API_BASE" ]; then
                  echo "ℹ️  Note: No API keys detected."
              fi
              unset SSH_ASKPASS_REQUIRE
            '';
          };

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
          packages = {
            n8n-image = nixos-generators.nixosGenerate {
              inherit system;
              modules = [
                ./hosts/n8n/configuration.nix
                { nixpkgs.config.allowUnfree = true; }
              ];
              format = "lxc";
              specialArgs = { inherit inputs; };
            };

            open-webui-image = nixos-generators.nixosGenerate {
              inherit system;
              modules = [
                ./hosts/open-webui/configuration.nix
                { nixpkgs.config.allowUnfree = true; }
              ];
              format = "lxc";
              specialArgs = { inherit inputs; };
            };
          };
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
