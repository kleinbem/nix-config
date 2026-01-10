{
  description = "Tofu/Terraform Infrastructure for NixOS Fleet";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    terranix = {
      url = "github:terranix/terranix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      terranix,
    }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
    in
    {
      # The Terraform Configuration (JSON)
      packages.${system}.config = terranix.lib.terranixConfiguration {
        inherit system;
        modules = [ ./config.nix ];
      };

      # DevShell with OpenTofu pre-installed
      devShells.${system}.default = pkgs.mkShell {
        buildInputs = [
          pkgs.opentofu
          terranix.packages.${system}.terranix
        ];
        shellHook = ''
          echo "🏗️  Terranix Infrastructure Shell"
          echo "   - Run 'nix run' to generate config.tf.json"
          echo "   - Run 'tofu init' and 'tofu apply' to deploy"
        '';
      };

      # Runnable App: nix run .
      apps.${system}.default = {
        type = "app";
        program = toString (
          pkgs.writeShellScript "generate-config" ''
            cp -f ${self.packages.${system}.config} config.tf.json
            echo "✅ Generated config.tf.json"
          ''
        );
      };
    };
}
