# workstation.nix — bundle for primary-desktop hosts (nixos-nvme).
#
# After the home-manager promotion to base.nix, only true desktop machines
# need this file. RPi nodes, NASbook, routers, and the orin-nano edge device
# use `headless.nix` instead. Foundational bits (my.* schema, sops-nix,
# home-manager, common overlays, locale, nix settings) live in `base.nix`.
#
# This file owns: desktop-specific overlays (NUR for community packages,
# VSCode extensions, nix-topology diagrams, nixpkgs-master), Lynis/hardening,
# snapper (btrfs snapshots), lanzaboote (UEFI Secure Boot), and Avahi mDNS
# with reflector (cross-bridge discovery).
{
  inputs,
  ...
}:
{
  # Desktop-only overlays. Universal `nix-packages` and `stable` overlays
  # live in base.nix.
  nixpkgs.overlays = [
    inputs.nur.overlays.default
    inputs.nix-vscode-extensions.overlays.default
    inputs.nix-topology.overlays.default
    (_final: prev: {
      master = import inputs.nixpkgs-master {
        inherit (prev.stdenv.hostPlatform) system;
        config.allowUnfree = true;
      };
    })
  ];

  imports = [
    ./hardening.nix
    ./snapper.nix
    inputs.lanzaboote.nixosModules.lanzaboote
  ];

  services.avahi = {
    enable = true;
    nssmdns4 = true;
    reflector = true; # Allow mDNS discovery across the container bridge
    publish = {
      enable = true;
      addresses = true;
      workstation = true;
      userServices = true;
    };
    openFirewall = true;
  };
}
