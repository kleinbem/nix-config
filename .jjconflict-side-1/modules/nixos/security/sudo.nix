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
          command = "/run/current-system/sw/bin/systemctl restart container@*";
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
      ];
    }
  ];
}
