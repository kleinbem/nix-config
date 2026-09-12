{ inputs, ... }:
{
  imports = [
    inputs.nix-presets.homeManagerModules.vcs
    inputs.nix-presets.homeManagerModules.terminal
    ./dev.nix
    ./ai-agents.nix
    inputs.nix-presets.homeManagerModules.desktop
    ./security.nix
    ./pentesting.nix
    ./vscode.nix
    ./nixvim.nix
    ./secrets.nix
    ./syncthing.nix
    ./service-launchers.nix
    ./workspace-guardian.nix
    inputs.nix-presets.homeManagerModules.opencode
    inputs.nix-presets.homeManagerModules.dx
    inputs.nix-presets.homeManagerModules.herdr
  ];
}
