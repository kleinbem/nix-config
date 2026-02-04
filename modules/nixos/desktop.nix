{
  pkgs,
  lib,
  config,
  ...
}:

let
  cfg = config.my.desktop;
in
{
  options.my.desktop = {
    enable = lib.mkEnableOption "Desktop Environment (Cosmic)";
  };

  config = lib.mkIf cfg.enable {
    # ==========================================
    # DESKTOP (COSMIC)
    # ==========================================
    boot.plymouth = {
      enable = true;
      theme = "bgrt";
    };

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
    environment = {
      sessionVariables.NIXOS_OZONE_WL = "1";

      etc."chromium/policies/managed/lab_policies.json".text = builtins.toJSON {
        # 1. Ephemeral Session (Wipe on Close) - DISABLED for IDE Compatibility
        ClearSiteDataOnExit = false;
        # 2. Privacy (Block 3rd party cookies) - DISABLED for IDE Compatibility
        BlockThirdPartyCookies = false;
        # 3. No Sync (It is a throwaway browser)
        SignInAllowed = false;
        # 4. DevTools enabled by default
        DeveloperToolsAvailability = 1;

        # 5. Disable Telemetry
        MetricsReportingEnabled = false;
        SpellCheckServiceEnabled = false;

        # 6. Add uBlock Origin Automatically
        # This installs uBlock Origin (lite or full) by default for all users
        ExtensionSettings = {
          "cjpalhdlnbpafiamejdnhcphjbkeiagm" = {
            # uBlock Origin ID
            installation_mode = "force_installed";
            update_url = "https://clients2.google.com/service/update2/crx";
          };
        };

        # 7. Debloat Brave (Crypto/VPN)
        BraveWalletDisabled = true;
        BraveRewardsDisabled = true;
        BraveVPNDisabled = true;
        # Leo AI is kept enabled per user request
      };

      systemPackages = with pkgs; [
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

        # Browsers
        nyxt
        ladybird

        # GUI Tools
        zoom-us
        bleachbit

        # CLI Tools
        just
      ];
    };

    fonts.fontconfig.enable = true;

    programs.xwayland.enable = true;
  };
}
