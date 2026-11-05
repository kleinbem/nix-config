# Deterministic policy checks over the evaluated host configs (lib/policy/).
# Eval-level only, so the required `check` job runs them on every PR. They
# read every host's config regardless of its system, hence x86_64-linux only.
{ inputs, self, ... }:
let
  inherit (inputs.nixpkgs) lib;
  common = import ../../lib/policy/common.nix { inherit lib; };
  secrets = import ../../lib/policy/secrets.nix { inherit lib; };
  state = import ../../lib/policy/state.nix { inherit lib common; };
  modes = import ../../lib/policy/modes.nix { inherit lib common; };

  # Hosts that boot: the factories only build containers and the bootstrap
  # image is a throwaway installer.
  hosts = lib.mapAttrs (_: h: h.config) (
    lib.filterAttrs (
      name: _: !(lib.hasPrefix "container-factory" name) && name != "orin-nano-bootstrap"
    ) self.nixosConfigurations
  );

  # Every module in modules/nixos with nothing enabled. Bundles that switch
  # features on, and files that aren't modules, stay out.
  notModules = [
    "keys.nix" # data
    "headless.nix" # tier bundle; its imports are listed on their own
    "workstation.nix" # tier bundle
    "pull-deploy-node.nix" # profile that turns autoUpgrade on
    "rpi5-node.nix" # hardware bundle
    "rpi5-disko.nix" # disk layout
  ];
  nixosModules = lib.filter (
    p: lib.hasSuffix ".nix" (toString p) && !(lib.elem (baseNameOf (toString p)) notModules)
  ) (lib.filesystem.listFilesRecursive ../nixos);

  defaultOff =
    extra:
    (inputs.nixpkgs.lib.nixosSystem {
      specialArgs = { inherit inputs self; };
      modules = nixosModules ++ [
        {
          _module.args = {
            myInventory = import ../../inventory.nix;
            secretFile = import ../../lib/secret-file.nix { inherit inputs; };
          };
          nixpkgs = {
            hostPlatform = "x86_64-linux";
            config.allowUnfree = true;
          };
          networking.hostName = "policy-default-off";
          fileSystems."/" = {
            device = "none";
            fsType = "tmpfs";
          };
          boot.loader.grub.enable = false;
          system.stateVersion = "25.05";
        }
        inputs.nix-flatpak.nixosModules.nix-flatpak
        inputs.disko.nixosModules.disko
        inputs.nix-presets.nixosModules.all
        inputs.nix-gantry.nixosModules.host
        inputs.nix-gantry.nixosModules.host-persistence
        inputs.nix-gantry.nixosModules.updater
        extra
      ];
    }).config;
in
{
  perSystem =
    { system, ... }:
    {
      checks = lib.optionalAttrs (system == "x86_64-linux") (
        let
          pkgs = inputs.nixpkgs.legacyPackages.${system};
        in
        {
          policy-secrets-gated = common.mkCheck pkgs "secrets-gated" (secrets.violations hosts defaultOff);
          policy-state-persisted = common.mkCheck pkgs "state-persisted" (state.violations hosts);
          policy-key-dir-modes = common.mkCheck pkgs "key-dir-modes" (
            lib.concatLists (lib.mapAttrsToList modes hosts)
          );
        }
      );
    };
}
