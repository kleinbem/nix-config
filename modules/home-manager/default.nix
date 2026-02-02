{ inputs, ... }:
{
  imports = [
    inputs.nix-presets.homeManagerModules.terminal
    ./dev.nix
    inputs.nix-presets.homeManagerModules.desktop
    ./security.nix
    ./pentesting.nix
    ./vscode.nix
    ./nixvim.nix
    ./secrets.nix
    inputs.nix-presets.homeManagerModules.opencode
  ];
}
