{
  description = "My NixOS Configuration Flake";

  # Inputs: Sources for packages
  inputs = {
    # I want to use the unstable branch because I like living on the edge (and newer python versions)
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
  };

  # Outputs: What this flake actually produces based on the inputs
  outputs = { self, nixpkgs, ... }@inputs: {
    nixosConfigurations = {
      
      # 'nixos' here must match the output of the 'hostname' command
      # If my hostname is different, I need to rename this key
      nixos-nvme = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          # I am importing the existing configuration.nix I just copied
          ./configuration.nix
        ];
      };
      
    };
  };
}
