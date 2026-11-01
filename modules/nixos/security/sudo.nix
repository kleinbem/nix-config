# Per-command sudo allowlist for the operator account, fleet-wide (imported
# via core.nix on every host).
#
#   readOnly  queries that change nothing. NOPASSWD.
#   power     reboot/poweroff with exact args. NOPASSWD: it boots an already
#             authenticated generation, so it can't escalate.
#   operate   unit and container lifecycle, regex-bounded. NOPASSWD so agents
#             can restart services and start nixos-upgrade.service. Unit names
#             exclude `@`, `.` and leading `-` because template instances take
#             arbitrary input (podman-kube@<any yaml>), so `start *` would be root.
#   deploy    root-equivalent (profile switches, container shells,
#             systemd-run). Authenticates like any sudo call (see headless.nix).
#
# sudoers: the LAST matching entry wins. So deploy comes first, then the
# read-only `machinectl shell * <cmd>` patterns override it, and the
# operateDenied negations come last to beat every allow, `%wheel ALL` included.
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
    # Manual container staging (nix-gantry's container-stage, or a bypass
    # when the CI manifest is broken).
    "${sw}/nix-env --profile /nix/var/nix/profiles/containers/* --set *"
    "/nix/store/*-nix-*/bin/nix-env --profile /nix/var/nix/profiles/containers/* --set *"
    # Swaps /var/lib/machines/<name>/current to the newly-registered
    # profile — the other half of the manual container-staging bypass.
    "${sw}/ln -sfn /nix/var/nix/profiles/containers/* /var/lib/machines/*/current"
    "${sw}/mkdir -p /var/lib/machines/*"
    "${sw}/machinectl shell *"
    # Real stdin/stdout piping into a container (machinectl shell is a PTY);
    # persona-scaffold.sh uses it to call Stalwart's API.
    "${sw}/systemd-run --machine=* --pipe --quiet --wait *"
  ];

  # `""` means "no arguments" in sudoers; a bare command would accept any.
  # reboot/poweroff are systemctl under another argv[0], hence exact args.
  power = [
    "${sw}/reboot \"\""
    "${sw}/poweroff \"\""
    "${sw}/systemctl reboot"
    "${sw}/systemctl poweroff"
    "${sw}/systemctl reboot --firmware-setup"
    "${sw}/shutdown -r now"
    "${sw}/shutdown -h now"
  ];

  # sudoers regex: the path stays literal, the argument string is matched
  # as `^…$` (POSIX ERE). `:`, `,`, `=` and `\` would need sudoers
  # escaping, so the patterns avoid them.
  unit = "[A-Za-z0-9][A-Za-z0-9_-]*([.]service|[.]timer|[.]socket)?";
  machine = "[A-Za-z0-9][A-Za-z0-9_-]*";
  operate = [
    "${sw}/systemctl ^(start|stop|restart|try-restart|reload|reload-or-restart|reset-failed) ${unit}( ${unit})*$"
    "${sw}/systemctl daemon-reload"
    "${sw}/systemctl reset-failed"
    "${sw}/machinectl ^(start|stop|restart|reboot|poweroff|terminate) ${machine}$"
  ];

  # Matches anywhere in an operate command: a root console on tty9, or
  # single-user mode on a host nobody is sitting at.
  operateDenied = [
    "${sw}/systemctl ^.*(debug-shell|emergency|rescue).*$"
  ];

  journalArg = "(-u [A-Za-z0-9@._-]+|-f|-b|-b -?[0-9]+|-e|-x|-xe|-k|-n [0-9]+|-p [0-7a-z]+|-o (short|short-iso|cat|json)|--no-pager)";

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
    # Viewing flags only: a `*` here would also pass --vacuum-*, --rotate
    # or --flush, which delete or move logs as root.
    "${sw}/journalctl ^${journalArg}( ${journalArg})*$"
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
    # Bare `dmesg` would accept any arguments, including -C (clear the
    # ring buffer) and -n (console log level).
    "${sw}/dmesg \"\""
    "${sw}/ss -tulpn"
    "${sw}/smartctl ^-[aHix]+ /dev/[a-z0-9]+$"
  ];
in
{
  options.my.security.sudo.unattendedDeploy = lib.mkOption {
    type = lib.types.bool;
    default = false;
    description = ''
      Keep the deploy tier of the sudo allowlist (system/container
      switches, container shells, systemd-run) passwordless on this
      host. Only for hosts that still receive unattended push deploys;
      everything else authenticates. The read-only, power and operate
      tiers are always passwordless.
    '';
  };

  config.security.sudo.extraRules = [
    {
      users = [ user ];
      commands = mkCommands (lib.optional cfg.unattendedDeploy "NOPASSWD") deploy;
    }
    {
      users = [ user ];
      commands = mkCommands [ "NOPASSWD" ] (power ++ operate ++ readOnly);
    }
    # Last, so the denial wins over both the rule above and %wheel ALL.
    {
      users = [ user ];
      commands = mkCommands [ ] (map (c: "!${c}") operateDenied);
    }
  ];
}
