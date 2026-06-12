{ ... }:
{
  imports = [
    ./clamav.nix
    ./smartcard.nix
    ./ssh.nix
    ./usbguard.nix
    ./airlock.nix
    ./sudo.nix
    ./hardening.nix
  ];
}
