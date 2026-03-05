{ ... }:
{
  imports = [
    ./core.nix
    ./desktop.nix
    ./users.nix
    ./security.nix
    ./printing.nix
    ./virtualisation.nix
    ./zero-trust.nix
    ./pki.nix

    # Services
    ./backup.nix
    ./scripts.nix
    ./services/github-runner.nix
    ./services/glances.nix
    ./services/redroid.nix
  ];
}
