# Per-command sudo allowlist for the operator account, fleet-wide (imported
# via core.nix on every host).
#
# Two tiers, deliberately:
#
#   readOnly  — queries that cannot change anything (nft list, journalctl,
#               systemctl status/list/show, machinectl show/status/list,
#               a few read-only commands *inside* containers). NOPASSWD.
#   deploy    — everything that mutates the system: system/container
#               profile switches, starting/stopping units, root shells in
#               containers, systemd-run. These authenticate like any other
#               sudo call (password on the workstation, pam_rssh touch key
#               or password on headless hosts — see headless.nix).
#
# Before 2026-10-20 the whole list was NOPASSWD. Several entries are root
# with extra steps (`machinectl shell *` → `.host`, `systemd-run
# --machine=* … *`, an unrestricted `nixos-rebuild`/`nh os switch` that
# will happily switch to any flake the user can write), so a passwordless
# allowlist meant: any process running as the operator user — an AI
# agent, a browser, a build hook — was root on every host, and the
# touch-key sudo design in headless.nix was decorative.
#
# sudoers semantics: when several entries match, the LAST match wins. The
# deploy rule therefore comes first and the read-only rule second, so the
# narrow read-only `machinectl shell * <cmd>` patterns override the broad
# `machinectl shell *` deploy entry.
#
# `my.security.sudo.unattendedDeploy = true` keeps the deploy tier
# passwordless on a host that still needs push deploys without a human
# at the keyboard (colmena with SSH_AUTH_SOCK="" — see
# .just/deployment.just — cannot answer a sudo prompt). Default off; the
# pull-deploy path (nixos-upgrade.service, container-updater) runs as
# root via systemd and never needed sudo in the first place.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.my.security.sudo;
  sw = "/run/current-system/sw/bin";
  user = config.my.username;

  mkCommands =
    options:
    map (command: {
      inherit command options;
    });

  deploy = [
    "${lib.getExe pkgs.nh} os switch"
    "${lib.getExe pkgs.nh} os boot"
    "/nix/store/*-nixos-system-*/bin/switch-to-configuration switch"
    "/nix/store/*-nixos-system-*/bin/switch-to-configuration boot"
    "/nix/store/*-nixos-system-*/bin/switch-to-configuration test"
    "${sw}/nixos-rebuild"
    "${sw}/nix-env --profile /nix/var/nix/profiles/system --set *"
    "/nix/store/*-nix-*/bin/nix-env --profile /nix/var/nix/profiles/system --set *"
    # Standalone container manual staging (nix-gantry's container-stage
    # script, or a manual bypass when the CI-published manifest is
    # stale/broken) — same profile-based swap as the system profile
    # above, just under /nix/var/nix/profiles/containers/.
    "${sw}/nix-env --profile /nix/var/nix/profiles/containers/* --set *"
    "/nix/store/*-nix-*/bin/nix-env --profile /nix/var/nix/profiles/containers/* --set *"
    # Swaps /var/lib/machines/<name>/current to the newly-registered
    # profile — the other half of the manual container-staging bypass.
    "${sw}/ln -sfn /nix/var/nix/profiles/containers/* /var/lib/machines/*/current"
    "${sw}/mkdir -p /var/lib/machines/*"
    "${sw}/machinectl shell *"
    "${sw}/machinectl start *"
    "${sw}/machinectl stop *"
    "${sw}/machinectl restart *"
    "${sw}/systemctl start *"
    "${sw}/systemctl stop *"
    "${sw}/systemctl restart *"
    "${sw}/systemctl reload *"
    "${sw}/systemctl daemon-reload"
    # Runs a one-off command inside a container's namespace via a
    # transient unit, with real stdin/stdout piping (unlike
    # `machinectl shell`'s PTY) — needed by persona-scaffold.sh to
    # POST to Stalwart's /api/principal from inside the stalwart
    # container.
    "${sw}/systemd-run --machine=* --pipe --quiet --wait *"
  ];

  readOnly = [
    "${sw}/nft list table *"
    "${sw}/nft list ruleset"
    "${sw}/machinectl show *"
    "${sw}/machinectl status *"
    "${sw}/machinectl list"
    "${sw}/machinectl shell * ${sw}/ip addr"
    "${sw}/machinectl shell * ${sw}/ip route"
    "${sw}/machinectl shell * ${sw}/cat /etc/hosts"
    "${sw}/machinectl shell * ${sw}/cat /etc/resolv.conf"
    "${sw}/machinectl shell * ${sw}/systemctl status *"
    "${sw}/apparmor_status"
    "${sw}/journalctl -u * -f"
    "${sw}/journalctl -u *"
    "${sw}/journalctl -f"
    "${sw}/journalctl -f *"
    "${sw}/journalctl -b"
    "${sw}/journalctl -xe"
    "${sw}/systemctl list-units"
    "${sw}/systemctl list-units *"
    "${sw}/systemctl list-timers"
    "${sw}/systemctl list-timers *"
    "${sw}/systemctl list-jobs"
    "${sw}/systemctl cat *"
    "${sw}/systemctl show *"
    "${sw}/systemctl is-active *"
    "${sw}/systemctl is-enabled *"
    "${sw}/systemctl is-failed *"
    "${sw}/systemctl status *"
    "${sw}/systemd-analyze blame"
    "${sw}/systemd-analyze critical-chain"
    "${sw}/systemd-analyze critical-chain *"
  ];
in
{
  options.my.security.sudo.unattendedDeploy = lib.mkOption {
    type = lib.types.bool;
    default = false;
    description = ''
      Keep the deploy tier of the sudo allowlist (system/container
      switches, unit start/stop, container shells) passwordless on this
      host. Only for hosts that still receive unattended push deploys;
      everything else authenticates. The read-only tier is always
      passwordless.
    '';
  };

  config.security.sudo.extraRules = [
    {
      users = [ user ];
      commands = mkCommands (lib.optional cfg.unattendedDeploy "NOPASSWD") deploy;
    }
    {
      users = [ user ];
      commands = mkCommands [ "NOPASSWD" ] readOnly;
    }
  ];
}
