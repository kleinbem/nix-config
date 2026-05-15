{ inputs, ... }:
{
  perSystem =
    { system, ... }:
    {
      packages = {
        router-1-image =
          let
            myInventory = import ../../inventory.nix;
          in
          inputs.nixos-generators.nixosGenerate {
            inherit system;
            modules = [
              ../../hosts/router-1/default.nix
              { nixpkgs.config.allowUnfree = true; }
            ];
            format = "lxc";
            specialArgs = {
              inherit inputs myInventory;
              inherit (inputs) self;
            };
          };
      };
    };
}
