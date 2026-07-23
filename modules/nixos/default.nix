{ ... }:
{
  imports = [
    ./base.nix # foundational, imported by every entry-point bundle

    ./kernel.nix
    ./audit.nix
    ./audio.nix
    ./desktop.nix
    ./users.nix
    ./security
    ./snapper.nix
    ./printing.nix
    ./firejail.nix
    ./ai-hardening.nix
    ./ananicy.nix
    ./android.nix

    # Services
    ./scripts.nix
    ./services/tang.nix
    ./clevis-initrd.nix
    ./initrd-fan.nix
  ];
}
