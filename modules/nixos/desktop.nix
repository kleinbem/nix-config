{ pkgs, ... }:

{
  # ==========================================
  # DESKTOP (COSMIC)
  # ==========================================
  services = {
    displayManager.cosmic-greeter.enable = true;
    desktopManager.cosmic.enable = true;
    system76-scheduler.enable = true;
    power-profiles-daemon.enable = true; # Standard for power management
    flatpak.enable = true;

    pulseaudio.enable = false;
    pipewire = {
      enable = true;
      alsa.enable = true;
      alsa.support32Bit = true;
      pulse.enable = true;
      jack.enable = true;
    };

    dbus.enable = true;
    avahi = {
      enable = true;
      nssmdns4 = true;
      publish = {
        enable = false;
        userServices = true;
      };
    };
  };

  # Enable graphics acceleration (Required for COSMIC)
  hardware.graphics.enable = true;

  xdg.portal = {
    enable = true;
    extraPortals = [
      pkgs.xdg-desktop-portal-cosmic
      pkgs.xdg-desktop-portal-gtk
    ];
    config.common.default = "cosmic";
  };

  # Persistence for GSettings/Cosmic
  programs.dconf.enable = true;

  # Electron apps use Wayland natively
  environment.sessionVariables.NIXOS_OZONE_WL = "1";

  fonts.fontconfig.enable = true;

  programs.xwayland.enable = true;

  environment.systemPackages = with pkgs; [
    # Desktop Utilities
    libsForQt5.qt5.qtwayland
    qt6.qtwayland

    # Cosmic Apps (Core components like comp/shell are installed by the desktopManager module)
    cosmic-files
    cosmic-term
    cosmic-edit
    # cosmic-store # Broken on NixOS (Use Nix!)
    cosmic-screenshot
    cosmic-randr

    # GUI Tools

    bleachbit

    # CLI Tools
    just
  ];
}
