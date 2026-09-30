{ pkgs, ... }:
{
  security.sudo.extraRules = [
    {
      users = [ "martin" ];
      commands = [
        {
          command = "${pkgs.nh}/bin/nh os switch";
          options = [ "NOPASSWD" ];
        }
        {
          command = "${pkgs.nh}/bin/nh os boot";
          options = [ "NOPASSWD" ];
        }
        {
          command = "/nix/store/*-nixos-system-*/bin/switch-to-configuration switch";
          options = [ "NOPASSWD" ];
        }
        {
          command = "/nix/store/*-nixos-system-*/bin/switch-to-configuration boot";
          options = [ "NOPASSWD" ];
        }
        {
          command = "/nix/store/*-nixos-system-*/bin/switch-to-configuration test";
          options = [ "NOPASSWD" ];
        }
        {
          command = "/run/current-system/sw/bin/nixos-rebuild";
          options = [ "NOPASSWD" ];
        }
        {
          command = "/run/current-system/sw/bin/nix-env --profile /nix/var/nix/profiles/system --set *";
          options = [ "NOPASSWD" ];
        }
        {
          command = "/nix/store/*-nix-*/bin/nix-env --profile /nix/var/nix/profiles/system --set *";
          options = [ "NOPASSWD" ];
        }
        {
          # Standalone container manual staging (nix-gantry's container-stage
          # script, or a manual bypass when the CI-published manifest is
          # stale/broken) — same profile-based swap as the system profile
          # above, just under /nix/var/nix/profiles/containers/.
          command = "/run/current-system/sw/bin/nix-env --profile /nix/var/nix/profiles/containers/* --set *";
          options = [ "NOPASSWD" ];
        }
        {
          command = "/nix/store/*-nix-*/bin/nix-env --profile /nix/var/nix/profiles/containers/* --set *";
          options = [ "NOPASSWD" ];
        }
        {
          # Swaps /var/lib/machines/<name>/current to the newly-registered
          # profile — the other half of the manual container-staging bypass.
          command = "/run/current-system/sw/bin/ln -sfn /nix/var/nix/profiles/containers/* /var/lib/machines/*/current";
          options = [ "NOPASSWD" ];
        }
        {
          command = "/run/current-system/sw/bin/mkdir -p /var/lib/machines/*";
          options = [ "NOPASSWD" ];
        }
        {
          command = "/run/current-system/sw/bin/nft list table *";
          options = [ "NOPASSWD" ];
        }
        {
          command = "/run/current-system/sw/bin/machinectl show *";
          options = [ "NOPASSWD" ];
        }
        {
          command = "/run/current-system/sw/bin/systemctl start ollama.service";
          options = [ "NOPASSWD" ];
        }
        {
          command = "/run/current-system/sw/bin/systemctl stop ollama.service";
          options = [ "NOPASSWD" ];
        }
        {
          command = "/run/current-system/sw/bin/systemctl restart ollama.service";
          options = [ "NOPASSWD" ];
        }
        {
          command = "/run/current-system/sw/bin/systemctl start vllm.service";
          options = [ "NOPASSWD" ];
        }
        {
          command = "/run/current-system/sw/bin/systemctl stop vllm.service";
          options = [ "NOPASSWD" ];
        }
        {
          command = "/run/current-system/sw/bin/systemctl restart vllm.service";
          options = [ "NOPASSWD" ];
        }
        {
          command = "/run/current-system/sw/bin/nft list ruleset";
          options = [ "NOPASSWD" ];
        }
        {
          command = "/run/current-system/sw/bin/machinectl shell * /run/current-system/sw/bin/ip addr";
          options = [ "NOPASSWD" ];
        }
        {
          command = "/run/current-system/sw/bin/machinectl shell * /run/current-system/sw/bin/ip route";
          options = [ "NOPASSWD" ];
        }
        {
          command = "/run/current-system/sw/bin/machinectl shell * /run/current-system/sw/bin/cat /etc/hosts";
          options = [ "NOPASSWD" ];
        }
        {
          command = "/run/current-system/sw/bin/machinectl shell * /run/current-system/sw/bin/cat /etc/resolv.conf";
          options = [ "NOPASSWD" ];
        }
        {
          command = "/run/current-system/sw/bin/machinectl shell * /run/current-system/sw/bin/systemctl status *";
          options = [ "NOPASSWD" ];
        }
        {
          command = "/run/current-system/sw/bin/apparmor_status";
          options = [ "NOPASSWD" ];
        }
        {
          command = "/run/current-system/sw/bin/journalctl -u * -f";
          options = [ "NOPASSWD" ];
        }
        {
          command = "/run/current-system/sw/bin/journalctl -u *";
          options = [ "NOPASSWD" ];
        }
        {
          command = "/run/current-system/sw/bin/journalctl -f";
          options = [ "NOPASSWD" ];
        }
        {
          command = "/run/current-system/sw/bin/journalctl -f *";
          options = [ "NOPASSWD" ];
        }
        {
          command = "/run/current-system/sw/bin/journalctl -b";
          options = [ "NOPASSWD" ];
        }
        {
          command = "/run/current-system/sw/bin/journalctl -xe";
          options = [ "NOPASSWD" ];
        }
        {
          command = "/run/current-system/sw/bin/systemctl list-units";
          options = [ "NOPASSWD" ];
        }
        {
          command = "/run/current-system/sw/bin/systemctl list-units *";
          options = [ "NOPASSWD" ];
        }
        {
          command = "/run/current-system/sw/bin/systemctl list-timers";
          options = [ "NOPASSWD" ];
        }
        {
          command = "/run/current-system/sw/bin/systemctl list-timers *";
          options = [ "NOPASSWD" ];
        }
        {
          command = "/run/current-system/sw/bin/systemctl list-jobs";
          options = [ "NOPASSWD" ];
        }
        {
          command = "/run/current-system/sw/bin/systemctl cat *";
          options = [ "NOPASSWD" ];
        }
        {
          command = "/run/current-system/sw/bin/systemctl show *";
          options = [ "NOPASSWD" ];
        }
        {
          command = "/run/current-system/sw/bin/systemctl is-active *";
          options = [ "NOPASSWD" ];
        }
        {
          command = "/run/current-system/sw/bin/systemctl is-enabled *";
          options = [ "NOPASSWD" ];
        }
        {
          command = "/run/current-system/sw/bin/systemctl is-failed *";
          options = [ "NOPASSWD" ];
        }
        {
          command = "/run/current-system/sw/bin/systemd-analyze blame";
          options = [ "NOPASSWD" ];
        }
        {
          command = "/run/current-system/sw/bin/systemd-analyze critical-chain";
          options = [ "NOPASSWD" ];
        }
        {
          command = "/run/current-system/sw/bin/systemd-analyze critical-chain *";
          options = [ "NOPASSWD" ];
        }
        {
          command = "/run/current-system/sw/bin/machinectl shell *";
          options = [ "NOPASSWD" ];
        }
        {
          command = "/run/current-system/sw/bin/machinectl status *";
          options = [ "NOPASSWD" ];
        }
        {
          command = "/run/current-system/sw/bin/machinectl start *";
          options = [ "NOPASSWD" ];
        }
        {
          command = "/run/current-system/sw/bin/machinectl stop *";
          options = [ "NOPASSWD" ];
        }
        {
          command = "/run/current-system/sw/bin/machinectl restart *";
          options = [ "NOPASSWD" ];
        }
        {
          command = "/run/current-system/sw/bin/machinectl list";
          options = [ "NOPASSWD" ];
        }
        {
          command = "/run/current-system/sw/bin/systemctl status *";
          options = [ "NOPASSWD" ];
        }
        {
          command = "/run/current-system/sw/bin/systemctl start *";
          options = [ "NOPASSWD" ];
        }
        {
          command = "/run/current-system/sw/bin/systemctl stop *";
          options = [ "NOPASSWD" ];
        }
        {
          command = "/run/current-system/sw/bin/systemctl restart *";
          options = [ "NOPASSWD" ];
        }
        {
          command = "/run/current-system/sw/bin/systemctl reload *";
          options = [ "NOPASSWD" ];
        }
        {
          command = "/run/current-system/sw/bin/systemctl daemon-reload";
          options = [ "NOPASSWD" ];
        }
        {
          # Runs a one-off command inside a container's namespace via a
          # transient unit, with real stdin/stdout piping (unlike
          # `machinectl shell`'s PTY) — needed by persona-scaffold.sh to
          # POST to Stalwart's /api/principal from inside the stalwart
          # container. Wildcarded on --machine= and the trailing command so
          # it covers any container, matching the `machinectl shell *`
          # pattern above rather than one-off per invocation.
          command = "/run/current-system/sw/bin/systemd-run --machine=* --pipe --quiet --wait *";
          options = [ "NOPASSWD" ];
        }
      ];
    }
  ];
}
