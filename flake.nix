{
  description = "AI-Augmented NixOS with COSMIC and Nixpak";

  inputs = {
    # --- Core ---
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixpak = {
      url = "github:nixpak/nixpak";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # --- AI & Operations ---
    # Repo for Gemini CLI and other specialized agents
    llm-agents.url = "github:numtide/llm-agents.nix";

    # Secret Management
    sops-nix.url = "github:Mic92/sops-nix";
    sops-nix.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, home-manager, nixpak, llm-agents, sops-nix, ... }: 
  let
    system = "x86_64-linux";
    pkgs = nixpkgs.legacyPackages.${system};
  in {
    # ---------------------------------------------------------
    # 1. The Agentic Development Shell
    # Run `nix develop` to enter the AI-Workspace
    # ---------------------------------------------------------
    devShells.${system}.default = pkgs.mkShell {
      buildInputs = [
        # Aider is in standard nixpkgs
        pkgs.aider-chat
        
        # Gemini CLI is in the llm-agents flake
        llm-agents.packages.${system}.gemini-cli
        
        pkgs.statix           # Linting for AI
        pkgs.nixfmt-rfc-style # Formatting for AI
        pkgs.sops             # Secret editing
      ];

      # FIXED: Generic welcome message (no hardcoded model names)
      shellHook = ''
        echo "🤖 Spec-Driven NixOS Environment Loaded"
        echo "   - System: NixOS + COSMIC + Nixpak"
        echo "   - Tools: Aider, Statix, Nixfmt"
        
        if [ -z "$GEMINI_API_KEY" ] && [ -z "$OLLAMA_API_BASE" ]; then
            echo "ℹ️  Note: No API keys detected. Ensure you are running 'just local' or have set keys."
        fi
      '';
    };

    # ---------------------------------------------------------
    # 2. System Configurations
    # ---------------------------------------------------------
    nixosConfigurations = {
      nixos-nvme = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          # The moved configuration file
          ./hosts/nixos-nvme/default.nix
          
          # Modules
          sops-nix.nixosModules.sops
          home-manager.nixosModules.home-manager
          
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.extraSpecialArgs = { inherit nixpak; };
            
            # Updated path for home.nix
            home-manager.users.martin = import ./hosts/nixos-nvme/home.nix;
          }
        ];
      };
    };
  };
}