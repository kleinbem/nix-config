{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.my.deploy.autoUpgrade;
in
{
  options.my.deploy.autoUpgrade = {
    enable = lib.mkEnableOption ''
      Pull-based fleet deploy: the host periodically checks the
      `production` git tag on kleinbem/nix-config, and runs
      `nixos-rebuild switch` if the tag has moved past the
      currently-deployed generation. Replaces SSH-push deploys
      (colmena from CI) — hosts are the driver, network goes one
      way only (host → GitHub), offline hosts catch up next cycle.
    '';

    dates = lib.mkOption {
      type = lib.types.str;
      default = "*-*-* 04:00:00";
      description = ''
        systemd calendar spec for the polling cadence. Defaults to
        nightly 04:00. Hosts pick up the latest `production` tag at
        this time; if the tag hasn't moved since the last successful
        upgrade, the work is a cheap `git ls-remote` and no rebuild.
      '';
    };

    randomizedDelaySec = lib.mkOption {
      type = lib.types.str;
      default = "30min";
      description = ''
        Randomized jitter on top of `dates` — keeps the fleet from
        hammering GitHub at exactly the same second when scaled to
        many hosts.
      '';
    };

    allowReboot = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Whether to reboot after upgrade when kernel/initrd/systemd
        changed. Default false: stage the new generation as boot
        default but let the user trigger the reboot. Set true on
        servers where unattended reboot is acceptable.
      '';
    };

    hostName = lib.mkOption {
      type = lib.types.str;
      default = config.networking.hostName;
      description = ''
        nixosConfigurations attribute name to deploy. Defaults to
        the host's own networking.hostName, which matches the
        canonical naming. Override if the host's flake attribute
        diverges from networking.hostName.
      '';
    };

    flakeRef = lib.mkOption {
      type = lib.types.str;
      default = "github:kleinbem/nix-config?ref=production";
      description = ''
        Flake URL prefix the host pulls from. Defaults to the
        kleinbem/nix-config repo at the moving `production` tag.
        CI advances this tag after a successful build-all so hosts
        only pull configs that have already passed CI.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    system.autoUpgrade = {
      enable = true;
      flake = "${cfg.flakeRef}#${cfg.hostName}";
      flags = [
        "--refresh"
        "-L"
      ];
      inherit (cfg) dates randomizedDelaySec allowReboot;
      operation = "switch";
    };

    # Structured journald log post-switch, so Loki+Grafana can render
    # a fleet dashboard ("current generation per host") from one LogQL
    # query. The activation script runs after every successful switch.
    system.activationScripts.deployLog = lib.stringAfter [ "users" ] ''
      ${pkgs.systemd}/bin/systemd-cat -t nix-config-deploy -p info <<EOF
      event=switch host=${cfg.hostName} system=$(readlink -f /run/current-system) flake=${cfg.flakeRef}
      EOF
    '';
  };
}
