# What nix-detour's update action checks on the daily lock update
# (maintain.yml), per system: each host's installed packages (home-manager
# users' too) and its toplevel, whose error trace names everything else.
# A package that fails after the update gets held in kleinbem/nix-holds-fleet.
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
