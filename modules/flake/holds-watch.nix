# What nix-detour's update action checks on the daily lock update
# (maintain.yml), per system: the top-level packages each host installs
# (incl. its home-manager users'), and each host's toplevel, whose error
# trace names packages reached any other way (services, MCP configs). A
# package that fails after the update is one to hold in
# kleinbem/nix-holds-fleet.
{
  inputs,
  self,
  lib,
  ...
}:
let
  # nix-holds-fleet's input was named nix-holds before the rename.
  fleetInputs = inputs.nix-holds-fleet.inputs;
  inherit ((fleetInputs.nix-detour or fleetInputs.nix-holds).lib) watch;
  hosts = lib.filterAttrs (
    name: _: !(lib.hasPrefix "container-factory" name)
  ) self.nixosConfigurations;
  systems = [
    "x86_64-linux"
    "aarch64-linux"
  ];
  hostsOf = system: lib.filterAttrs (_: host: host.pkgs.stdenv.hostPlatform.system == system) hosts;
in
{
  flake.nixDetourWatch = lib.genAttrs systems (
    system:
    lib.foldl' (watched: host: watched // watch.nixos host) { } (lib.attrValues (hostsOf system))
  );
  flake.nixDetourTargets = lib.genAttrs systems (
    system: lib.mapAttrs (_: watch.target) (hostsOf system)
  );
}
