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
          permittedInsecurePackages = [
            "olivetin-2025.11.25"
          ];
        };
        overlays = [ inputs.nix-on-droid.overlays.default ];
      };
      extraSpecialArgs = { inherit inputs self myInventory; };
      modules = [ ../../hosts/phone/default.nix ];
    };
  };
}
