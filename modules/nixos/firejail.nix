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
        # Chrome is deliberately NOT firejailed. It ships its own
        # battle-tested multiprocess sandbox (unprivileged user-namespace +
        # seccomp-bpf), so firejail on top is largely redundant for the
        # compromised-renderer threat while adding a SUID-root binary to the
        # attack surface. More importantly, the firejail default profile's
        # private-dev / nou2f / nogroups restrictions break FIDO2/WebAuthn
        # with a YubiKey (the old firefox wrapper needed three --ignore=
        # escape hatches, and hotplug stayed flaky). Chrome is installed as a
        # plain package instead — nix-presets/desktop.nix for martin,
        # hosts/mac-mini/default.nix for that host.
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
