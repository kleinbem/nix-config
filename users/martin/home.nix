{
  inputs,
  pkgs,
  my,
  ...
}:
{
  imports = [
    ../../modules/home-manager/default.nix
    ../../modules/home-manager/gnome.nix
    inputs.nix-devshells.homeManagerModules.desktopLaunchers
  ];

  modules = {
    devshell-launchers.enable = true;
    service-launchers.enable = true;
    mcp.enable = true;
    opencode.enable = true;
    gnome.enable = true;
    syncthing.enable = false; # Migrated to system container fleet
  };

  # User Details
  home = {
    inherit (my) username;
    homeDirectory = my.home;
    stateVersion = "25.11";
    sessionVariables = {
      DEFAULT_BROWSER = "${pkgs.firefox-beta}/bin/firefox -P standard";
      BROWSER = "${pkgs.firefox-beta}/bin/firefox -P standard";
    };

    # Personal System Control Center — `os <ns>::<recipe>`. The `os`
    # shell alias lives in nix-presets/terminal.nix (generic); these
    # source files are martin-specific (Obsidian paths, etc.) and so
    # belong in martin's user dir rather than a shared preset.
    file = {
      ".justfile" = {
        source = ./files/justfile;
        force = true;
      };
      ".just" = {
        source = ./files/.just;
        recursive = true;
      };
    };
  };

  xdg.mimeApps = {
    enable = true;
    defaultApplications = {
      "text/html" = [ "firefox-standard.desktop" ];
      "x-scheme-handler/http" = [ "firefox-standard.desktop" ];
      "x-scheme-handler/https" = [ "firefox-standard.desktop" ];
      "x-scheme-handler/about" = [ "firefox-standard.desktop" ];
      "x-scheme-handler/unknown" = [ "firefox-standard.desktop" ];
    };
  };

  programs = {
    firefox-browser.enable = true;
    home-manager.enable = true;

    # Inject hardware-protected signing keys from centralized proxy
    git.settings.user.signingKey = "${my.home}/.ssh/id_ed25519_sk_rk_GitHubNoTouch.pub";
    # jj's ssh backend wants a public-key file path; the `key::<blob>` form
    # is git-specific and silently breaks signing in jj.
    jujutsu.settings.signing.key = "${my.home}/.ssh/id_ed25519_sk_rk_GitHubNoTouch.pub";

    # SSH multiplexing for github.com — first touch-required FIDO op opens a
    # master connection; subsequent SSH ops within ControlPersist reuse it
    # without a fresh touch. Dramatically reduces YubiKey touches during
    # `just apply` (was ~6 touches per apply, now typically 1-2).
    #
    # If stale sockets ever cause "Session open refused by peer" hangs, run:
    #   ssh -O exit git@github.com 2>/dev/null; rm -f ~/.ssh/cm-*
    ssh = {
      enable = true;
      matchBlocks = {
        "github.com" = {
          hostname = "github.com";
          user = "git";
          extraOptions = {
            ControlMaster = "auto";
            ControlPath = "~/.ssh/cm-%r@%h:%p";
            ControlPersist = "10m";
          };
        };
      };
    };
  };

  # Desktop Launchers
  xdg.desktopEntries = {
    "launch-nested-dhirujaan" = {
      name = "Nested Session (Dhirujaan)";
      genericName = "Lightweight Wayland Session";
      exec = "sudo /home/martin/Develop/github.com/kleinbem/nix/nix-config/scripts/launch-nested.sh";
      icon = "system-users";
      terminal = true;
      categories = [ "System" ];
    };
  };

  # Silencing evaluation warnings from newer Home Manager
  # (Using null adopts the new default behavior)
  gtk.gtk4.theme = null;
}
