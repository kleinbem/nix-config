{
  pkgs,
  inputs,
  ...
}:

{
  imports = [
    inputs.sops-nix.homeManagerModules.sops
  ];

  sops = {
    defaultSopsFile = "${inputs.nix-secrets}/secrets.yaml";
    defaultSopsFormat = "yaml";
    age.keyFile = "/home/martin/.config/sops/age/host.txt";

    package =
      pkgs.runCommand "sops-with-plugins"
        {
          nativeBuildInputs = [ pkgs.makeWrapper ];
        }
        ''
          mkdir -p $out/bin
          makeWrapper ${pkgs.sops}/bin/sops $out/bin/sops \
            --prefix PATH : "${pkgs.age-plugin-yubikey}/bin:${pkgs.age-plugin-tpm}/bin"
          makeWrapper ${
            inputs.sops-nix.packages.${pkgs.system}.sops-install-secrets
          }/bin/sops-install-secrets $out/bin/sops-install-secrets \
            --prefix PATH : "${pkgs.age-plugin-yubikey}/bin:${pkgs.age-plugin-tpm}/bin"
        '';

  };
}
