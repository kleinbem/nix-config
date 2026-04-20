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
    ./pki.nix
    ./ai-hardening.nix
    ./networking.nix

    # Services
    ./backup.nix
    ./scripts.nix
    ./services/github-runner.nix
    ./services/redroid.nix
  ];
}
