{ pkgs, ... }:

{
  programs.firejail = {
    enable = true;
    wrappedBinaries = {
      firefox = {
        executable = "${pkgs.firefox-beta}/bin/firefox";
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
      signal-desktop = {
        executable = "${pkgs.signal-desktop}/bin/signal-desktop";
        profile = "${pkgs.firejail}/etc/firejail/signal-desktop.profile";
      };
      obsidian = {
        executable = "${pkgs.obsidian}/bin/obsidian";
        profile = "${pkgs.firejail}/etc/firejail/obsidian.profile";
      };
      mpv = {
        executable = "${pkgs.mpv}/bin/mpv";
        profile = "${pkgs.firejail}/etc/firejail/mpv.profile";
      };
      bitwarden = {
        executable = "${pkgs.bitwarden-desktop}/bin/bitwarden";
        profile = "${pkgs.firejail}/etc/firejail/bitwarden.profile";
      };
      lmstudio = {
        executable = "${pkgs.lmstudio}/bin/lmstudio";
        profile = "${pkgs.firejail}/etc/firejail/electron.profile"; # Fallback for LM Studio
      };
      logseq = {
        executable = "${pkgs.logseq}/bin/logseq";
        profile = "${pkgs.firejail}/etc/firejail/logseq.profile";
      };
      obs-studio = {
        executable = "${pkgs.obs-studio}/bin/obs";
        profile = "${pkgs.firejail}/etc/firejail/obs.profile";
      };
      chromium = {
        executable = "${pkgs.chromium}/bin/chromium";
        profile = "${pkgs.firejail}/etc/firejail/chromium.profile";
        extraArgs = [ "--noblacklist=/etc/cups" ];
      };
      github-desktop = {
        executable = "${pkgs.github-desktop}/bin/github-desktop";
        profile = "${pkgs.firejail}/etc/firejail/github-desktop.profile";
      };
      zathura = {
        executable = "${pkgs.zathura}/bin/zathura";
        profile = "${pkgs.firejail}/etc/firejail/zathura.profile";
      };
      zotero = {
        executable = "${pkgs.zotero}/bin/zotero";
        profile = "${pkgs.firejail}/etc/firejail/zotero.profile";
      };
    };
  };

}
