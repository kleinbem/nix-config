{
  pkgs,
  lib,
  config,
  ...
}:

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
        obsidian = {
          executable = "${pkgs.obsidian}/bin/obsidian";
          profile = "${pkgs.firejail}/etc/firejail/obsidian.profile";
        };
        obs-studio = {
          executable = "${pkgs.obs-studio}/bin/obs";
          profile = "${pkgs.firejail}/etc/firejail/obs.profile";
        };
        # Chrome is not firejailed: its own sandbox covers the renderer, and
        # firejail's private-dev/nou2f/nogroups break YubiKey WebAuthn. It's a
        # plain package (nix-presets/desktop.nix, hosts/mac-mini).
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
