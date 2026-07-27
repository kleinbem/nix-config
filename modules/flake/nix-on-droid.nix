{ inputs, self, ... }:
let
  myInventory = import ../../inventory.nix;
in
{
  flake.nixOnDroidConfigurations = {
    phone = inputs.nix-on-droid.lib.nixOnDroidConfiguration {
      pkgs = import inputs.nixpkgs {
        system = "aarch64-linux";
        config = {
          allowUnfree = true;
          allowInsecurePredicate = pkg: inputs.nixpkgs.lib.getName pkg == "olivetin";
        };
        overlays = [ inputs.nix-on-droid.overlays.default ];
      };
      extraSpecialArgs = { inherit inputs self myInventory; };
      modules = [ ../../hosts/phone/default.nix ];
    };
  };
}
