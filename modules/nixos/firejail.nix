{ pkgs, ... }:

{
  programs.firejail = {
    enable = true;
    wrappedBinaries = {
      firefox = {
        executable = "${pkgs.firefox-beta}/bin/firefox";
        profile = "${pkgs.firejail}/etc/firejail/firefox.profile";
        extraArgs = [ "--dns=1.1.1.1" ];
      };
      google-chrome-stable = {
        executable = "${pkgs.google-chrome}/bin/google-chrome-stable";
        profile = "${pkgs.firejail}/etc/firejail/google-chrome.profile";
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
    };
  };

  environment.systemPackages = with pkgs; [
    firetools # The graphical UI for Firejail
  ];
}
