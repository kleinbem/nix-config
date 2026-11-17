# Foyer's "Needs attention" feed: a timer writes attention.json from public
# GitHub data (no token), and the dashboard container serves the directory
# under /feed/ (my.containers.dashboard.feedDir).
{ lib, pkgs, ... }:
let
  feedDir = "/run/foyer-feed";
  generate = pkgs.writeShellApplication {
    name = "foyer-attention";
    runtimeInputs = with pkgs; [
      coreutils
      curl
      jq
    ];
    text = builtins.readFile ./foyer-attention.sh;
  };
in
{
  users = {
    users.foyer-feed = {
      isSystemUser = true;
      group = "foyer-feed";
    };
    groups.foyer-feed = { };
  };

  # The container's bind mount needs the directory before the first run.
  systemd.tmpfiles.rules = [ "d ${feedDir} 0755 foyer-feed foyer-feed -" ];

  my.containers.dashboard.feedDir = feedDir;

  systemd = {
    services.foyer-attention = {
      description = "Generate Foyer's attention feed";
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];
      environment = {
        FEED_DIR = feedDir;
        GITHUB_USER = "kleinbem";
        # Their default branch gates every deploy.
        WATCH_REPOS = "kleinbem/nix-config kleinbem/nix-presets";
      };
      serviceConfig = {
        Type = "oneshot";
        ExecStart = lib.getExe generate;
        User = "foyer-feed";
        Group = "foyer-feed";
        ReadWritePaths = [ feedDir ];
        CapabilityBoundingSet = "";
        LockPersonality = true;
        MemoryDenyWriteExecute = true;
        NoNewPrivileges = true;
        PrivateDevices = true;
        PrivateTmp = true;
        ProtectClock = true;
        ProtectControlGroups = true;
        ProtectHome = true;
        ProtectHostname = true;
        ProtectKernelLogs = true;
        ProtectKernelModules = true;
        ProtectKernelTunables = true;
        ProtectSystem = "strict";
        RestrictAddressFamilies = [
          "AF_INET"
          "AF_INET6"
          "AF_UNIX"
        ];
        RestrictNamespaces = true;
        RestrictRealtime = true;
        SystemCallArchitectures = "native";
      };
    };

    # Six runs an hour stay far below GitHub's unauthenticated limits
    # (10 searches a minute, 60 other requests an hour).
    timers.foyer-attention = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "2min";
        OnUnitActiveSec = "10min";
        RandomizedDelaySec = "1min";
      };
    };
  };
}
