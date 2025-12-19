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

    # Secret Management
    sops-nix.url = "github:Mic92/sops-nix";
    sops-nix.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, home-manager, nixpak, sops-nix, ... }@inputs: 
  let
    system = "x86_64-linux";
    pkgs = nixpkgs.legacyPackages.${system};
  in {
    # ---------------------------------------------------------
    # 1. The Agentic Development Shell
    # ---------------------------------------------------------
    devShells.${system}.default = pkgs.mkShell {
      buildInputs = [
        pkgs.aider-chat
        pkgs.gemini-cli
        pkgs.statix            
        pkgs.nixfmt-rfc-style 
        pkgs.sops
        
        # --- Secret Management Tools ---
        pkgs.age
        pkgs.age-plugin-yubikey
      ];

      shellHook = ''
        echo "🤖 Spec-Driven NixOS Environment Loaded"
        echo "   - System: NixOS + COSMIC + Nixpak"
        
        if [ -z "$GEMINI_API_KEY" ] && [ -z "$OLLAMA_API_BASE" ]; then
            echo "ℹ️  Note: No API keys detected."
        fi
      '';
    };

    # ---------------------------------------------------------
    # 2. System Configurations
    # ---------------------------------------------------------
    nixosConfigurations = {
      nixos-nvme = nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = { inherit inputs; };
        
        modules = [
          ./hosts/nixos-nvme/default.nix
          
          sops-nix.nixosModules.sops
          home-manager.nixosModules.home-manager
          
          {
            home-manager = {
              useGlobalPkgs = true;
              useUserPackages = true;
              extraSpecialArgs = { inherit nixpak; };
              users.martin = import ./hosts/nixos-nvme/home.nix;
            };
          }
        ];
      };
    };
  };
}
