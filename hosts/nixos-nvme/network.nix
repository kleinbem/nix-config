{
  pkgs,
  myInventory,
  ...
}:

{

  networking = {
    hostName = "nixos-nvme";
    # code-server and syncthing both rely entirely on Caddy's forward_auth
    # (Authentik, was Authelia until 2026-09-22) for access control:
    # code-server runs with `auth = "none"`
    # (nix-presets/containers/code-server.nix) and syncthing's GUI has no
    # username/password configured (nix-presets/containers/syncthing.nix) —
    # neither has any auth of its own. Both container ports were reachable
    # directly, bypassing Caddy/forward_auth entirely: confirmed live
    # 2026-09-19, curling either one directly returned the full app (VS
    # Code workbench / Syncthing GUI) with no login prompt at all — worse
    # than the paperless bug fixed earlier the same day (that one at least
    # needed a spoofed header; these need nothing).
    #
    # Same root cause as nasbook: networking.firewall.extraForwardRules
    # (what container-host.nix uses) only exists on the nftables firewall
    # backend; nixos-nvme uses the classic iptables backend
    # (networking.firewall.backend == "iptables"), where it's silently
    # inert. networking.nat.extraCommands is the correct injection point
    # for that backend — appended into nat-iptables.nix's
    # "nixos-filter-forward" chain, which otherwise only has an
    # unconditional cbr0->WAN accept + established/related accept before
    # falling through to the kernel's default ACCEPT forward policy (why
    # this was so easily exploitable, including cross-host —
    # network-routing.nix routes every host's container subnet to every
    # other host). 10.85.46.1 is nixos-nvme's own bridge address, allowed
    # for host-side debugging/administration.
    nat.extraCommands = ''
      iptables -w -t filter -A nixos-filter-forward -d ${myInventory.network.nodes.code-server.ip} -p tcp --dport ${toString myInventory.network.nodes.code-server.port} -s ${myInventory.network.nodes.caddy.ip} -j ACCEPT
      iptables -w -t filter -A nixos-filter-forward -d ${myInventory.network.nodes.code-server.ip} -p tcp --dport ${toString myInventory.network.nodes.code-server.port} -s 10.85.46.1 -j ACCEPT
      iptables -w -t filter -A nixos-filter-forward -d ${myInventory.network.nodes.code-server.ip} -p tcp --dport ${toString myInventory.network.nodes.code-server.port} -j DROP
      iptables -w -t filter -A nixos-filter-forward -d ${myInventory.network.nodes.syncthing.ip} -p tcp --dport ${toString myInventory.network.nodes.syncthing.port} -s ${myInventory.network.nodes.caddy.ip} -j ACCEPT
      iptables -w -t filter -A nixos-filter-forward -d ${myInventory.network.nodes.syncthing.ip} -p tcp --dport ${toString myInventory.network.nodes.syncthing.port} -s 10.85.46.1 -j ACCEPT
      iptables -w -t filter -A nixos-filter-forward -d ${myInventory.network.nodes.syncthing.ip} -p tcp --dport ${toString myInventory.network.nodes.syncthing.port} -j DROP
    '';
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

      # Zero Trust: NetBird is NOT blanket-trusted.
      # Only specific ports are open over the tunnel.
      interfaces."wt0".allowedTCPPorts = [
        22 # SSH
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
    };
  };

  services = {
    netbird = {
      enable = true;
      ui.enable = true; # Adds the NetBird GUI/Tray Icon
    };

  };

  systemd.services = {
  };
}
