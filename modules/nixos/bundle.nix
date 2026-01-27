{
  imports = [
    ./core.nix
    ./desktop.nix
    ./users.nix
    ./security.nix
    ./printing.nix
    ./virtualisation.nix

    # Restored Services
    ./ai-services.nix
    ./backup.nix
    ./scripts.nix
    ./services/dashboard.nix
    ./services/github-runner.nix
    ./services/code-server.nix
    ./services/silverbullet.nix
  ];
}
