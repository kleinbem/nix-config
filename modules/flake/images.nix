{ self, inputs, ... }:
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
        if system == "x86_64-linux" then
          let
            containers = self.nixosConfigurations.container-factory.config.containers;
          in
          {
            container-caddy = containers.caddy.path;
            container-n8n = containers.n8n.path;
            container-code-server = containers."code-server".path;
          }
        else
          { }
      );
    };
}
