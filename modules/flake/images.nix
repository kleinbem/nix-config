{ self, ... }:
{
  perSystem =
    { system, lib, ... }:
    {
      packages =
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
        );
    };
}
