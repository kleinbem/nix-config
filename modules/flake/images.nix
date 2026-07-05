{ self, inputs, ... }:
{
  perSystem =
    { system, lib, ... }:
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
              {
                nixpkgs = {
                  config.allowUnfree = true;
                  buildPlatform = "x86_64-linux";
                  hostPlatform = "aarch64-linux";
                };
              }
            ];
            format = "lxc";
            specialArgs = {
              inherit inputs myInventory;
              inherit (inputs) self;
            };
          };
      }
      // (
        # Expose whatever the arch's factory actually builds as
        # `container-<name>` packages. The factory set is deployment-driven
        # (ADR 002), so this tracks reality instead of a hardcoded list.
        let
          factory =
            {
              x86_64-linux = self.nixosConfigurations.container-factory or null;
              aarch64-linux = self.nixosConfigurations.container-factory-aarch64 or null;
            }
            .${system} or null;
        in
        lib.optionalAttrs (factory != null) (
          lib.mapAttrs' (name: c: lib.nameValuePair "container-${name}" c.path) factory.config.containers
        )
      );
    };
}
