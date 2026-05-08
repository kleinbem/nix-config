{ pkgs, ... }:

let
  mkExtension =
    {
      name,
      uuid,
      owner,
      repo,
      rev,
      hash,
    }:
    pkgs.stdenv.mkDerivation {
      pname = name;
      version = rev;
      src = pkgs.fetchFromGitHub {
        inherit
          owner
          repo
          rev
          hash
          ;
      };
      installPhase = ''
        mkdir -p $out/share/gnome-shell/extensions/${uuid}
        cp -r * $out/share/gnome-shell/extensions/${uuid}
      '';
      passthru.extensionUuid = uuid;
    };

  bazaar-companion = mkExtension {
    name = "gnome-extension-bazaar-companion";
    uuid = "bazaar-integration@kolunmi.github.io";
    owner = "bazaar-org";
    repo = "bazaar-companion";
    rev = "3bb9134985343ffd1993520eb37c90e113bfb09b";
    hash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
  };

  custom-command-menu = mkExtension {
    name = "gnome-extension-custom-command-menu";
    uuid = "custom-command-list@storageb.github.com";
    owner = "StorageB";
    repo = "custom-command-menu";
    rev = "494a4a82199dfcd7138d4aa71eedb189f605da9d";
    hash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
  };

in
{
  environment.systemPackages = [
    bazaar-companion
    custom-command-menu
  ];
}
