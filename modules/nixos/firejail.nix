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
  config =
    lib.mkIf
      (config.my.desktop.enable || config.my.desktop.gnome.enable || config.my.desktop.lite.enable)
      {
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
                "--ignore=nogroups" # Required for some USB hardware access
                "--dbus-user.talk=org.freedesktop.secrets" # Allow access to GNOME Keyring
              ];
            };
            firefox-devedition = {
              executable = "${pkgs.firefox-devedition}/bin/firefox-devedition";
              profile = "${pkgs.firejail}/etc/firejail/firefox.profile";
              extraArgs = [
                "--noblacklist=/etc/cups"
                "--ignore=private-dev"
                "--ignore=nogroups"
                "--dbus-user.talk=org.freedesktop.secrets"
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
            bitwarden = {
              executable = "${pkgs.bitwarden-desktop}/bin/bitwarden";
              profile = "${pkgs.firejail}/etc/firejail/bitwarden.profile";
            };
            logseq = {
              executable = "${pkgs.logseq}/bin/logseq";
              profile = "${pkgs.firejail}/etc/firejail/logseq.profile";
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
