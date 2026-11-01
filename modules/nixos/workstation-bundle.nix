# Workstation bundle: every workstation-only module (GUI, audio, printing,
# hardening, dev tooling). Import base.nix separately; this only adds the
# workstation tier on top.

{ ... }:
{
  imports = [
    # Kernel & Performance
    ./kernel.nix

    # Security & Audit
    ./audit.nix
    ./security

    # Audio & Media
    ./audio.nix

    # Desktop Environment
    ./desktop.nix
    ./firejail.nix

    # User Setup
    ./users.nix

    # System Maintenance
    ./snapper.nix

    # Hardware Support
    ./printing.nix
    ./threed-printing.nix
    ./android.nix

    # AI/Performance
    ./ai-hardening.nix
    ./ananicy.nix

    # Boot & Initialization
    ./clevis-initrd.nix
    ./initrd-fan.nix

    # System Scripts & Utilities
    ./scripts.nix

    # Services
    ./services/tang.nix
    ./services/langfuse.nix
  ];
}
