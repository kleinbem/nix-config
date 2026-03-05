{ my, pkgs, ... }:
{
  imports = [ ../../modules/home-manager/default.nix ];

  modules.opencode.enable = true;

  # User Details
  home = {
    inherit (my) username;
    homeDirectory = my.home;
    stateVersion = "24.11";
  };

  programs.firefox = {
    enable = true;
    profiles.default = {
      # 1. Basic Profile Info
      id = 0;
      name = "default";
      isDefault = true;

      # 2. Hardening via userPref (The "Arkenfox" approach)
      settings = {
        # --- PRIVACY & TRACKING ---
        "privacy.resistFingerprinting" = true; # Blocks many hardware-based tracking methods
        "privacy.trackingprotection.enabled" = true;
        "privacy.trackingprotection.socialtracking.enabled" = true;
        "privacy.firstparty.isolate" = true; # Isolates cookies to the website that set them

        # --- SECURITY BITS ---
        "dom.event.clipboardevents.enabled" = false; # Stops sites from knowing when you copy/paste
        "media.peerconnection.enabled" = false; # Disables WebRTC to prevent IP leaks (breaks some video calls)
        "network.dns.disableIPv6" = true; # Optional: helps if your VPN/ISP has IPv6 leaks

        # --- CLEANUP (TELEMETRY & BLOAT) ---
        "datareporting.healthreport.uploadEnabled" = false;
        "toolkit.telemetry.enabled" = false;
        "browser.newtabpage.activity-stream.feeds.telemetry" = false;
        "browser.newtabpage.activity-stream.telemetry" = false;
        "extensions.pocket.enabled" = false; # Goodbye, Pocket
        "browser.topsites.controversial.enabled" = false;

        # --- CONVENIENCE (Optional) ---
        "browser.download.panel.shown" = true;
        "browser.startup.page" = 3; # Resume previous session
        "identity.fxaccounts.enabled" = false; # Disable Firefox Sync if you don't use it
      };

      # 3. Pre-install Security Extensions
      extensions.packages = with pkgs.nur.repos.rycee.firefox-addons; [
        ublock-origin
        privacy-badger
        bitwarden
        # multi-account-containers # Great for dev work (separating prod/dev logins)
      ];
    };
  };

  # Host-specific tweaks can stay here if needed
  # (e.g. monitor config, unique vars)
  programs.home-manager.enable = true;
}
