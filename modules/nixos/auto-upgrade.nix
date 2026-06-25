{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.my.deploy.autoUpgrade;

  # Pre-flight gate for `nixos-upgrade.service`. The Attic binary cache is only
  # reachable over the NetBird mesh (wt0 -> caddy DNAT). The fixed nightly timer
  # can fire before the mesh has reconverged after a relay/peer blip; when that
  # happens the upgrade can't substitute and falls back to compiling the whole
  # closure locally (observed: a 4h16m / 16-CPU-hour kernel rebuild on hass-pi).
  # This probe retries for ~2min to let NetBird converge, then aborts the cycle
  # (the host simply catches up on the next run) instead of melting the CPU.
  # Any HTTP response — including 401, since the cache requires auth — counts as
  # "reachable"; only a connection/timeout failure counts as "down".
  cacheProbe = pkgs.writeShellScript "autoupgrade-cache-gate" ''
    export PATH=${
      lib.makeBinPath [
        pkgs.curl
        pkgs.coreutils
      ]
    }
    url="${cfg.cacheUrl}/nix-cache-info"
    for i in $(seq 1 8); do
      if curl -sS --max-time 10 -o /dev/null "$url"; then
        echo "auto-upgrade: cache reachable ($url) on attempt $i"
        exit 0
      fi
      echo "auto-upgrade: cache unreachable (attempt $i/8); waiting for NetBird to converge..."
      sleep 15
    done
    echo "auto-upgrade: cache $url unreachable after ~2min; skipping this cycle (catches up next run)"
    exit 1
  '';
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

    requireCache = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Harden the pull for cache-dependent hosts (ARM/Pi nodes that
        substitute everything from Attic over the NetBird mesh and are
        never meant to compile locally). When true:
          1. order `nixos-upgrade.service` after `netbird.service` /
             `network-online.target` so it doesn't start before the mesh,
          2. add a pre-flight probe that waits up to ~2min for the binary
             cache (`cacheUrl`) to become reachable and aborts the cycle if
             it can't be reached (instead of building the closure locally),
          3. cap the run with `RuntimeMaxSec = maxRuntime` so a cache miss
             that slips past the probe can't run away into a multi-hour
             on-device build — the run is killed and retried next cycle.
        Leave false for hosts that can legitimately build locally
        (e.g. the x86 workstation).
      '';
    };

    cacheUrl = lib.mkOption {
      type = lib.types.str;
      default = "https://cache.kleinbem.dev/system";
      description = ''
        Binary cache the `requireCache` pre-flight probe checks for
        reachability before allowing an upgrade run to proceed.
      '';
    };

    maxRuntime = lib.mkOption {
      type = lib.types.str;
      default = "30min";
      description = ''
        `RuntimeMaxSec` for `nixos-upgrade.service` when `requireCache`
        is set. A build-free substitute-only pull finishes in well under
        a minute; this cap exists to kill a runaway local build (kernel
        recompile) rather than let it hammer the host for hours. Raise it
        if a host legitimately needs to download very large closures over
        a slow link.
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

    # Cache-dependent hosts: order after the mesh, gate on cache reachability,
    # and cap runtime so a cache miss can't trigger a multi-hour local rebuild.
    systemd.services.nixos-upgrade = lib.mkIf cfg.requireCache {
      after = [
        "network-online.target"
        "netbird.service"
      ];
      wants = [ "network-online.target" ];
      serviceConfig = {
        ExecStartPre = [ "${cacheProbe}" ];
        RuntimeMaxSec = cfg.maxRuntime;
      };
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
