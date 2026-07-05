{
  pkgs,
  lib,
  myInventory,
  ...
}:

{
  # cache.kleinbem.dev must resolve to the LOCAL caddy container here — this
  # host's own NetBird IP (the module default) would miss the PREROUTING
  # port-forward for locally-originated traffic. attic-pull.nix owns the
  # /etc/hosts entry.
  my.atticPull.cacheHostIp = "10.85.46.107";

  networking = {
    hostName = "nixos-nvme";
    # TODO: remove once OpenWrt router is enrolled in NetBird and pushes DNS nameserver rules.
    # NetBird peer IPs are stable, but this bypasses proper split-DNS.
    hosts."100.117.61.169" = [
      "orin-nano.netbird.cloud"
      "orin-nano"
    ];
    networkmanager = {
      enable = true;
      plugins = [ pkgs.networkmanager-openvpn ];
      # Stop Wi-Fi MAC randomization so the workstation keeps a stable DHCP lease
      # (Tang host for the Orin's headless LUKS unlock must stay put — see
      # docs / openwrt static_leases). extraConfig was removed upstream → settings.
      settings = {
        device."wifi.scan-rand-mac-address" = "no";
        connection = {
          "wifi.cloned-mac-address" = "permanent";
          "ethernet.cloned-mac-address" = "permanent";
        };
      };
    };
    # Fix Routing for the Ricoh Printer subnet (10.0.x.x)
    interfaces.wlo1.ipv4.routes = [
      {
        address = "10.0.0.0";
        prefixLength = 16;
      }
    ];
    firewall = {
      enable = true;
      # Open all ports that Caddy is proxying to allow external access
      allowedTCPPorts = lib.mapAttrsToList (_: node: node.externalPort) (
        lib.filterAttrs (_: v: v ? externalPort) myInventory.network.nodes
      );

      # Zero Trust: NetBird is NOT blanket-trusted.
      # Only specific ports are open over the tunnel.
      interfaces."wt0".allowedTCPPorts = [
        22 # SSH
        443 # Caddy HTTPS (access all services via reverse proxy)
      ];
      # Tang (LUKS auto-unlock for orin-nano) on the LAN/Wi-Fi interface only
      interfaces."wlo1".allowedTCPPorts = [ 7654 ];
      allowedTCPPortRanges = [
        {
          from = 1714;
          to = 1764;
        } # KDE Connect (GSConnect)
      ];
      allowedUDPPortRanges = [
        {
          from = 1714;
          to = 1764;
        } # KDE Connect (GSConnect)
      ];
      extraForwardRules = ''
        # Allow NetBird traffic that was NAT'd to reach the Caddy container
        iifname "wt0" oifname "${myInventory.network.bridge}" ip daddr ${myInventory.network.nodes.caddy.ip} tcp dport { 80, 443 } accept
      '';
    };
    nftables.enable = true;
    nftables.tables.netbird-nat = {
      family = "inet";
      content = ''
        chain prerouting {
          type nat hook prerouting priority dstnat; policy accept;
          iifname "wt0" tcp dport { 80, 443 } dnat ip to ${myInventory.network.nodes.caddy.ip}
        }
      '';
    };
  };

  services = {
    netbird = {
      enable = true;
      ui.enable = true; # Adds the NetBird GUI/Tray Icon
    };

    # Host-level CrowdSec Firewall Bouncer
    crowdsec-firewall-bouncer = {
      enable = false;
      secrets.apiKeyPath = "/var/lib/images/crowdsec/bouncer-key";
      settings = {
        api_url = "http://${myInventory.network.nodes.crowdsec.ip}:8080/";
        api_keyfile = "/var/lib/images/crowdsec/bouncer-key";
      };
    };
  };

  systemd.services = {
  };
}
