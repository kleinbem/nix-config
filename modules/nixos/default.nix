{ ... }:
{
  imports = [
    ./kernel.nix
    ./audit.nix
    ./core.nix
    ./desktop.nix
    ./users.nix
    ./security.nix
    ./snapper.nix
    ./printing.nix
    ./virtualisation.nix
    ./zero-trust.nix
    ./firejail.nix
    ./pki.nix
    ./ai-hardening.nix
    ./networking.nix
    ./ananicy.nix

    # Services
    ./backup.nix
    ./scripts.nix
    ./services/redroid.nix
  ];
}
