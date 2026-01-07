{
  description = "AI-Augmented NixOS with COSMIC and Nixpak";

  inputs = {
    # --- Core ---
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixpkgs-stable.url = "github:NixOS/nixpkgs/nixos-25.11";

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
      url = "git+ssh://git@github.com/kleinbem/nix-secrets.git";
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
      url = "github:nix-community/lanzaboote"; # Use master to fix build issues
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixvim = {
      url = "github:nix-community/nixvim";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      nixpak,
      treefmt-nix,
      pre-commit-hooks,
      nixos-generators,
      ...
    }@inputs:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};

      # Treefmt Configuration
      treefmtEval = treefmt-nix.lib.evalModule pkgs {
        projectRootFile = "flake.nix";
        programs.nixfmt.enable = true;
      };

      # Import Custom Library
      mylib = import ./lib/mkSystem.nix { inherit nixpkgs inputs nixpak; };
    in
    {
      # ---------------------------------------------------------
      # 1. The Agentic Development Shell
      # ---------------------------------------------------------
      formatter.${system} = treefmtEval.config.build.wrapper;

      devShells.${system}.default = pkgs.mkShell {
        buildInputs = [
          pkgs.aider-chat
          # pkgs.gemini-cli ## temp disabled

          pkgs.statix
          pkgs.nixfmt-rfc-style
          pkgs.deadnix
          pkgs.sops

          # --- Secret Management Tools ---
          pkgs.age
          pkgs.age-plugin-yubikey

          # Generative
          nixos-generators.packages.${system}.nixos-generate
        ];

        shellHook = ''
          ${self.checks.${system}.pre-commit-check.shellHook}
          echo "🤖 Spec-Driven NixOS Environment Loaded"
          echo "   - System: NixOS + COSMIC + Nixpak"

          if [ -z "$GEMINI_API_KEY" ] && [ -z "$OLLAMA_API_BASE" ]; then
              echo "ℹ️  Note: No API keys detected."
          fi

          # Unset SSH_ASKPASS_REQUIRE to allow YubiKey interaction
          unset SSH_ASKPASS_REQUIRE
        '';
      };

      # ---------------------------------------------------------
      # 2. Checks (Pre-commit)
      # ---------------------------------------------------------
      checks.${system}.pre-commit-check = pre-commit-hooks.lib.${system}.run {
        src = ./.;
        hooks = {
          nixfmt-rfc-style.enable = true;
          statix.enable = true;
          deadnix.enable = true;
        };
      };

      # ---------------------------------------------------------
      # 3. System Configurations
      # ---------------------------------------------------------
      nixosConfigurations = {
        nixos-nvme = mylib.mkSystem {
          hostname = "nixos-nvme";
          user = "martin";
        };
      };
    };
}
