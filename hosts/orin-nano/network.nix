{ lib, pkgs, ... }:
{
  services = {
    netbird.enable = true;
    openssh = {
      enable = true;
      settings = {
        PasswordAuthentication = false;
        # Disable 2FA for SSH — colmena deploys non-interactively and cannot
        # provide TOTP. Publickey-only is sufficient on a LAN-only service.
        AuthenticationMethods = lib.mkForce "publickey";
      };
    };

    # systemd-resolved as the local DNS resolver — integrates cleanly with NetBird
    # and provides fallback DNS even when NetBird is disconnected.
    resolved = {
      enable = true;
      # Migrated to the new option path (was `fallbackDns` / `dnssec`).
      settings.Resolve.FallbackDNS = "1.1.1.1 8.8.8.8";
      settings.Resolve.DNSSEC = "false";
    };
  };

  networking = {
    # systemd-resolved manages DNS; disable resolvconf to avoid conflict with networking.nix
    resolvconf.enable = lib.mkForce false;
    nameservers = [
      "1.1.1.1"
      "8.8.8.8"
    ];
    # Container bridge — needed by frigate/syncthing nspawn containers
    bridges."cbr0".interfaces = [ ];
    useDHCP = false;
    interfaces = {
      "enP8p1s0" = {
        ipv4 = {
          addresses = [
            {
              address = "10.0.0.15";
              prefixLength = 16;
            }
          ];
          # Suppress static routes from network-routing.nix — other hosts' container
          # subnets (10.85.47-49.0/24) are not routable from the Orin's 10.0.0.x LAN,
          # and 10.85.46.0/24 is used locally by cbr0 on this host.
          routes = lib.mkForce [ ];
        };
      };
      "cbr0".ipv4.addresses = [
        {
          address = "10.85.46.1";
          prefixLength = 24;
        }
      ];
    };
    defaultGateway = {
      address = "10.0.0.1";
      interface = "enP8p1s0";
    };
    # NVIDIA's JetPack 6 vendor kernel (5.15.199-tegra) defconfig lacks
    # CONFIG_NFT_CT, CONFIG_NFT_REDIR, and CONFIG_NFT_FIB_IPV4, preventing
    # nftables from loading connection-tracking or redirect rules.
    # Legacy iptables/xtables (CONFIG_IP_NF_*, CONFIG_NETFILTER_XT_*) is fully
    # supported. Revert to iptables backend on JetPack 6.
    nftables.enable = false;
    nat = {
      enable = true;
      internalInterfaces = [ "cbr0" ];
      externalInterface = "enP8p1s0";
      forwardPorts = [
        {
          sourcePort = 11434;
          destination = "10.85.46.126:11434";
          proto = "tcp";
        }
      ];
      # Hairpin NAT and mesh forwarding for llama-cpp over NetBird/LAN
      extraCommands = ''
        iptables -w -t nat -A PREROUTING -p tcp --dport 11434 -j DNAT --to-destination 10.85.46.126:11434
        iptables -w -t nat -A POSTROUTING -d 10.85.46.126 -p tcp --dport 11434 -j MASQUERADE
        iptables -w -t filter -A FORWARD -d 10.85.46.126 -p tcp --dport 11434 -j ACCEPT
      '';
      extraStopCommands = ''
        iptables -w -t nat -D PREROUTING -p tcp --dport 11434 -j DNAT --to-destination 10.85.46.126:11434 2>/dev/null || true
        iptables -w -t nat -D POSTROUTING -d 10.85.46.126 -p tcp --dport 11434 -j MASQUERADE 2>/dev/null || true
        iptables -w -t filter -D FORWARD -d 10.85.46.126 -p tcp --dport 11434 -j ACCEPT 2>/dev/null || true
      '';
    };
    firewall = {
      enable = true;
      backend = "iptables";
      package = pkgs.iptables-legacy;
      trustedInterfaces = [ "cbr0" ];
      # SSH only over NetBird — not exposed on LAN
      interfaces."wt0".allowedTCPPorts = [
        22
        11434
      ];
      # Also allow SSH on LAN for emergency access (e.g. before NetBird is running)
      interfaces."enP8p1s0".allowedTCPPorts = [
        22
        11434
      ];
    };
  };

  systemd = {
    services.enforce-container-routes.enable = lib.mkForce false;
    timers.enforce-container-routes.enable = lib.mkForce false;
  };
}
