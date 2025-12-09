{ pkgs, ... }:

pkgs.stdenv.mkDerivation rec {
  pname = "ricoh-official-driver";
  version = "1.01";

  # This points to the file named 'ricoh-driver.rpm' in the same folder
  src = ./ricoh-driver.rpm;

  nativeBuildInputs = [
    pkgs.rpmextract
    pkgs.autoPatchelfHook
  ];

  # These are the libraries the binary driver usually needs
  buildInputs = [
    pkgs.cups
    pkgs.ghostscript
    pkgs.glibc
  ];

  unpackPhase = ''
    rpmextract $src
  '';

  installPhase = ''
    mkdir -p $out
    
    # 1. Copy the standard unix structure from the RPM
    cp -r usr/* $out/

    # 2. Fix PPD location for NixOS CUPS
    mkdir -p $out/share/cups/model/ricoh
    find $out -name "*.ppd" -exec cp {} $out/share/cups/model/ricoh/ \;

    # 3. Fix Filter Permissions (MUST be executable)
    find $out/lib/cups/filter -type f -exec chmod +x {} \;
  '';
}