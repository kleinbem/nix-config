{
  pkgs,
  myInventory,
  ...
}:

{

  networking = {
    hostName = "nixos-nvme";
    # Needed besides firewall.backend: with nftables.enable = false,
    # nat-iptables.nix always injects extraCommands, which the nftables
    # firewall then rejects by assertion.
    nftables.enable = true;
    # TODO: remove once OpenWrt router is enrolled in NetBird and pushes DNS nameserver rules.
    # no-link: internal infra migration (router NetBird enrollment).
    # NetBird peer IPs are stable, but this bypasses proper split-DNS.
    hosts.${myInventory.hosts.orin-nano.netbirdIp} = [
      "orin-nano.netbird.cloud"
      "orin-nano"
    ];
    networkmanager = {
      enable = true;
      plugins = [ pkgs.networkmanager-openvpn ];
      # Stop Wi-Fi MAC randomization so the workstation keeps a stable DHCP lease
      # (Tang host for the Orin's headless LUKS unlock must stay put).
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

      # extraForwardRules (used by forward-auth-guard.nix) is nftables-only
      # and silently inert on the iptables backend.
      backend = "nftables";

      # Without this the nftables firewall emits no forward chain, so
      # extraForwardRules is silently dropped.
      filterForward = true;

      # revue has no login: only Caddy may reach it, and Caddy puts Authentik
      # in front. Same sources as forward-auth-guard.nix.
      extraInputRules = ''
        ip saddr { ${myInventory.hosts.core-pi.ip}, ${myInventory.network.nodes.caddy.ip} } tcp dport ${toString myInventory.network.nodes.revue.port} accept comment "revue only via Caddy"
      '';

      # Zero Trust: NetBird is NOT blanket-trusted.
      # Only specific ports are open over the tunnel.
      interfaces."wt0".allowedTCPPorts = [
        22 # SSH
        8384 # cadre web surface over mesh
        8385 # nix-detour web dashboard over mesh
      ];
      # Tang, cadre, nix-detour on the LAN/Wi-Fi interface
      interfaces."wlo1".allowedTCPPorts = [
        7654
        8384
        8385
      ];
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
