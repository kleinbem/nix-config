{
  pkgs,
  lib,
  config,
  ...
}:

let
  isX86 = pkgs.stdenv.hostPlatform.system == "x86_64-linux";
in
{
  config = lib.mkIf config.my.desktop.gnome.enable {
    programs.firejail = {
      enable = true;
      wrappedBinaries = {
        mpv = {
          executable = "${pkgs.mpv}/bin/mpv";
          profile = "${pkgs.firejail}/etc/firejail/mpv.profile";
        };
        chromium = {
          executable = "${pkgs.chromium}/bin/chromium";
          profile = "${pkgs.firejail}/etc/firejail/chromium.profile";
          extraArgs = [ "--noblacklist=/etc/cups" ];
        };
        zathura = {
          executable = "${pkgs.zathura}/bin/zathura";
          profile = "${pkgs.firejail}/etc/firejail/zathura.profile";
        };
      }
      // lib.optionalAttrs isX86 {
        firefox = {
          executable = "${pkgs.firefox-beta}/bin/firefox-beta";
          profile = "${pkgs.firejail}/etc/firejail/firefox.profile";
          extraArgs = [
            "--dns=1.1.1.1"
            "--noblacklist=/etc/cups"
            "--ignore=private-dev" # Required for YubiKey/FIDO2 access
            "--ignore=nou2f" # Required for YubiKey/WebAuthn access
            "--ignore=nogroups" # Required for some USB hardware access
            "--dbus-user.talk=org.freedesktop.secrets" # Allow access to GNOME Keyring
            "--dbus-user.talk=org.freedesktop.FileManager1" # Allow "Show in Folder" on downloads (opens Nautilus)
            # Extra save/open locations beyond the default ~/Downloads whitelist.
            # Keep this list intentional: anything NOT listed here is invisible
            # to Firefox (e.g. ~/Develop, SSH keys, secrets repos stay hidden).
            # Note the triple backslash: the nixpkgs firejail module splices
            # extraArgs into an UNQUOTED heredoc (programs/firejail.nix's
            # wrappedBins builder), so a plain "\${HOME}" gets expanded by
            # the *build sandbox's* shell (HOME=/homeless-shelter) instead
            # of staying literal for firejail to expand per-user at runtime.
            # "\\\${HOME}" survives that heredoc pass as a literal ${HOME}.
            "--whitelist=\\\${HOME}/Documents"
            "--whitelist=\\\${HOME}/Pictures"
            "--whitelist=\\\${HOME}/Desktop"
          ];
        };
        firefox-devedition = {
          executable = "${pkgs.firefox-devedition}/bin/firefox-devedition";
          profile = "${pkgs.firejail}/etc/firejail/firefox.profile";
          extraArgs = [
            "--noblacklist=/etc/cups"
            "--ignore=private-dev"
            "--ignore=nou2f"
            "--ignore=nogroups"
            "--dbus-user.talk=org.freedesktop.secrets"
            "--dbus-user.talk=org.freedesktop.FileManager1"
            # Note the triple backslash: the nixpkgs firejail module splices
            # extraArgs into an UNQUOTED heredoc (programs/firejail.nix's
            # wrappedBins builder), so a plain "\${HOME}" gets expanded by
            # the *build sandbox's* shell (HOME=/homeless-shelter) instead
            # of staying literal for firejail to expand per-user at runtime.
            # "\\\${HOME}" survives that heredoc pass as a literal ${HOME}.
            "--whitelist=\\\${HOME}/Documents"
            "--whitelist=\\\${HOME}/Pictures"
            "--whitelist=\\\${HOME}/Desktop"
          ];
        };
        signal-desktop = {
          executable = "${pkgs.signal-desktop}/bin/signal-desktop";
          profile = "${pkgs.firejail}/etc/firejail/signal-desktop.profile";
        };
        obsidian = {
          executable = "${pkgs.obsidian}/bin/obsidian";
          profile = "${pkgs.firejail}/etc/firejail/obsidian.profile";
        };
        obs-studio = {
          executable = "${pkgs.obs-studio}/bin/obs";
          profile = "${pkgs.firejail}/etc/firejail/obs.profile";
        };
        google-chrome-stable = {
          executable = "${pkgs.google-chrome}/bin/google-chrome-stable";
          profile = "${pkgs.firejail}/etc/firejail/google-chrome.profile";
          extraArgs = [ "--noblacklist=/etc/cups" ];
        };
        discord = {
          executable = "${pkgs.discord}/bin/discord";
          profile = "${pkgs.firejail}/etc/firejail/discord.profile";
        };
        slack = {
          executable = "${pkgs.slack}/bin/slack";
          profile = "${pkgs.firejail}/etc/firejail/slack.profile";
        };
        lmstudio = {
          executable = "${pkgs.lmstudio}/bin/lmstudio";
          profile = "${pkgs.firejail}/etc/firejail/electron.profile"; # Fallback for LM Studio
        };
        github-desktop = {
          executable = "${pkgs.github-desktop}/bin/github-desktop";
          profile = "${pkgs.firejail}/etc/firejail/github-desktop.profile";
        };
        zotero = {
          executable = "${pkgs.zotero}/bin/zotero";
          profile = "${pkgs.firejail}/etc/firejail/zotero.profile";
        };
      };
    };
  };
}
