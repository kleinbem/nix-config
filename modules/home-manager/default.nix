{ inputs, ... }:
{
  imports = [
    inputs.nix-presets.homeManagerModules.vcs
    inputs.nix-presets.homeManagerModules.terminal
    ./dev.nix
    ./ai-agents.nix
    inputs.nix-presets.homeManagerModules.desktop
    inputs.cadre.homeManagerModules.default
    ./security.nix
    ./vscode.nix
    ./nixvim.nix
    ./secrets.nix
    ./syncthing.nix
    ./service-launchers.nix
    inputs.nix-presets.homeManagerModules.opencode
    inputs.nix-presets.homeManagerModules.dx
    inputs.nix-presets.homeManagerModules.herdr
    ./android.nix
  ];
}
