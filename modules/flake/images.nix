{ inputs, ... }:
{
  perSystem =
    {
      system,
      ...
    }:
    {
      packages = {
        n8n-image = inputs.nixos-generators.nixosGenerate {
          inherit system;
          modules = [
            ../../hosts/n8n/configuration.nix
            { nixpkgs.config.allowUnfree = true; }
          ];
          format = "lxc";
          specialArgs = { inherit inputs; };
        };

        open-webui-image = inputs.nixos-generators.nixosGenerate {
          inherit system;
          modules = [
            ../../hosts/open-webui/configuration.nix
            { nixpkgs.config.allowUnfree = true; }
          ];
          format = "lxc";
          specialArgs = { inherit inputs; };
        };
      };
    };
}
