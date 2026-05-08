{ inputs, ... }:
{
  imports = [
    inputs.nix-presets.homeManagerModules.git
    inputs.nix-presets.homeManagerModules.terminal
    ./dev.nix
    inputs.nix-presets.homeManagerModules.desktop
    ./security.nix
    ./pentesting.nix
    ./vscode.nix
    ./nixvim.nix
    ./secrets.nix
    ./syncthing.nix
    ./service-launchers.nix
    inputs.nix-presets.homeManagerModules.firefox-browser
    inputs.nix-presets.homeManagerModules.opencode
    inputs.nix-presets.homeManagerModules.dx
  ];
}
