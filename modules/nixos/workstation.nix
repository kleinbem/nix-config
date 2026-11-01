# workstation.nix: bundle for desktop hosts (nixos-nvme); headless hosts use
# headless.nix, and the shared foundation is in base.nix.
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
    ./snapper.nix
    inputs.lanzaboote.nixosModules.lanzaboote
  ];

  services.avahi = {
    enable = true;
    nssmdns4 = true;
    settings = {
      reflector.enable-reflector = true; # Allow mDNS discovery across the container bridge
      publish = {
        disable-publishing = false;
        publish-addresses = true;
        publish-workstation = true;
        disable-user-service-publishing = false;
      };
    };
    openFirewall = true;
  };
}
