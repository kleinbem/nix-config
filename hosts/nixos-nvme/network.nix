{
  pkgs,
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
    # NetBird peer IPs are stable, but this bypasses proper split-DNS.
    hosts."100.117.61.169" = [
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
