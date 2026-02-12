{ inputs, ... }:
{
  imports = [
    ./core.nix
    ./desktop.nix
    ./users.nix
    ./security.nix
    ./printing.nix
    ./virtualisation.nix

    # Restored Services
    inputs.nix-android-emulator-setup.nixosModules.default
    ./ai-services.nix
    ./backup.nix
    ./scripts.nix
    ./services/github-runner.nix
    ./services/glances.nix
    ./services/redroid.nix
  ];
}
