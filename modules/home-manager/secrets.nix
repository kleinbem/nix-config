{
  pkgs,
  lib,
  inputs,
  config,
  secretFile,
  ...
}:

{
  imports = [
    inputs.sops-nix.homeManagerModules.sops
  ];

  sops = {
    defaultSopsFile = secretFile "nix/shared.yaml";
    defaultSopsFormat = "yaml";
    age.keyFile = "${config.home.homeDirectory}/.config/sops/age/host.txt";

    package =
      pkgs.runCommand "sops-with-plugins"
        {
          nativeBuildInputs = [ pkgs.makeBinaryWrapper ];
        }
        ''
          mkdir -p $out/bin
          makeWrapper ${lib.getExe pkgs.sops} $out/bin/sops \
            --prefix PATH : "${pkgs.age-plugin-yubikey}/bin:${pkgs.age-plugin-tpm}/bin"
          makeWrapper ${
            inputs.sops-nix.packages.${pkgs.stdenv.hostPlatform.system}.sops-install-secrets
          }/bin/sops-install-secrets $out/bin/sops-install-secrets \
            --prefix PATH : "${pkgs.age-plugin-yubikey}/bin:${pkgs.age-plugin-tpm}/bin"
        '';

  };

  # Use nano for sops editing (friendlier than nvim for YAML secrets)
  home.shellAliases.sops = "EDITOR=nano sops";
}
