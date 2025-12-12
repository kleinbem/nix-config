{
  description = "My NixOS config with COSMIC";

  inputs = {
    # Use unstable for fresh COSMIC + Wayland stuff
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixpak = {
      url = "github:nixpak/nixpak";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, home-manager, nixpak, ... }: {
    nixosConfigurations = {
      nixos-nvme = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          ./configuration.nix
          
          home-manager.nixosModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            
            home-manager.extraSpecialArgs = { inherit nixpak; }; 
            
            home-manager.users.martin = import ./home.nix;
          }
        ];
      };
    };
  };
}