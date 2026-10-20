{
  pkgs,
  ...
}:

{

  networking = {
    hostName = "nixos-nvme";
    # networking.nftables.enable is a second, separate flag from
    # firewall.backend: nixpkgs' legacy nat-iptables.nix module
    # unconditionally injects its iptables-flush teardown script into
    # networking.firewall.extraCommands whenever nftables.enable is false
    # — regardless of networking.nat.enable's own value (confirmed via its
    # source: `config = mkIf (!config.networking.nftables.enable) (mkMerge
    # [ { firewall.extraCommands = mkBefore flushNat; } ... ])`). Without
    # this, the nftables-backend firewall module's own assertion
    # ("extraCommands is incompatible with the nftables based firewall")
    # fails even with nat.enable=false and no manually-set extraCommands.
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

      # UPDATED 2026-09-22: switched to the nftables backend so
      # extraForwardRules (declarative, nftables-only) works here — was on
      # the classic iptables backend, where that option is silently inert
      # (same root cause hit on nasbook/mac-mini; see their own default.nix
      # for the matching note). container-host.nix is NOT imported on this
      # host, so its own broad "accept everything to/from the bridge"
      # extraForwardRules fragment doesn't exist here to worry about — but
      # the rules below are still wrapped in lib.mkBefore for defense in
      # depth, so they'd win the ordering race even if that ever changes.
      backend = "nftables";

      # extraForwardRules is silently unused without this: firewall-nftables.nix
      # only emits its "forward"/"forward-allow" chains at all (the ones that
      # actually consume extraForwardRules) when filterForward = true (default
      # false — confirmed via its source, `lib.optionalString cfg.filterForward
      # ''chain forward { ... forward-allow ... }''`). Found the hard way: the
      # resolved option value had the right content, but it never appeared
      # anywhere in the built ruleset until this was added.
      filterForward = true;

      # The per-port rules that used to live here (code-server/syncthing,
      # 2026-09-19/22 — incl. the lesson that Caddy's cross-host traffic
      # arrives masqueraded as core-pi's LAN address) moved to
      # modules/nixos/forward-auth-guard.nix, which derives the same
      # "only Caddy may reach this port" rule for every `auth = true`
      # inventory node on every nftables host.

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
