{ ... }:
{
  imports = [
    # Base tier (required by all configs)
    ./base.nix

    # Workstation-specific bundle (GUI, development, multimedia, etc.)
    # See workstation-bundle.nix for details.
    ./workstation-bundle.nix
  ];
}
