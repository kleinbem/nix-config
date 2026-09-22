{
  pkgs,
  lib,
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
    # UPDATED 2026-09-22: switched this host to the nftables firewall
    # backend so networking.firewall.extraForwardRules (declarative,
    # nftables-only) works here — was on the classic iptables backend,
    # where that option is silently inert (same root cause hit on
    # nasbook/mac-mini; see their own default.nix for the matching note).
    # container-host.nix is NOT imported on this host, so its own broad
    # "accept everything to/from the bridge" extraForwardRules fragment
    # doesn't exist here to worry about — but the rules below are still
    # wrapped in lib.mkBefore for defense in depth, so they'd win the
    # ordering race even if that ever changes.
    #
    # Original bug (2026-09-19): code-server and syncthing both rely
    # entirely on Caddy's forward_auth (Authentik, was Authelia until
    # 2026-09-22) for access control — code-server runs with `auth =
    # "none"` (nix-presets/containers/code-server.nix) and syncthing's GUI
    # has no username/password configured
    # (nix-presets/containers/syncthing.nix) — neither has any auth of its
    # own. Both container ports were reachable directly, bypassing
    # Caddy/forward_auth entirely: curling either one directly returned the
    # full app (VS Code workbench / Syncthing GUI) with no login prompt at
    # all.
    #
    # Second bug, found + fixed 2026-09-22 while verifying the above still
    # actually worked end-to-end (it never had been, cross-host): the
    # ACCEPT rule matched Caddy's raw container IP
    # (myInventory.network.nodes.caddy.ip, 10.85.48.107) as the allowed
    # source — but core-pi masquerades ALL cbr0->end0 egress unconditionally
    # (`iifname "cbr0" oifname "end0" masquerade`, confirmed live via `nft
    # list ruleset` on core-pi), so Caddy's cross-host traffic actually
    # arrives here as core-pi's own physical LAN address instead. Confirmed
    # via iptables rule counters (the old DROP line had real hits) before
    # switching to this backend. myInventory.hosts.core-pi.ip is that real,
    # masqueraded source. 10.85.46.1 is nixos-nvme's own bridge address,
    # allowed for host-side debugging/administration.
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
    firewall.backend = "nftables";
    # extraForwardRules is silently unused without this: firewall-nftables.nix
    # only emits its "forward"/"forward-allow" chains at all (the ones that
    # actually consume extraForwardRules) when filterForward = true (default
    # false — confirmed via its source, `lib.optionalString cfg.filterForward
    # ''chain forward { ... forward-allow ... }''`). Found the hard way: the
    # resolved option value had the right content, but it never appeared
    # anywhere in the built ruleset until this was added.
    firewall.filterForward = true;
    firewall.extraForwardRules = lib.mkBefore ''
      ip daddr ${myInventory.network.nodes.code-server.ip} tcp dport ${toString myInventory.network.nodes.code-server.port} ip saddr { ${myInventory.hosts.core-pi.ip}, 10.85.46.1 } accept
      ip daddr ${myInventory.network.nodes.code-server.ip} tcp dport ${toString myInventory.network.nodes.code-server.port} drop
      ip daddr ${myInventory.network.nodes.syncthing.ip} tcp dport ${toString myInventory.network.nodes.syncthing.port} ip saddr { ${myInventory.hosts.core-pi.ip}, 10.85.46.1 } accept
      ip daddr ${myInventory.network.nodes.syncthing.ip} tcp dport ${toString myInventory.network.nodes.syncthing.port} drop
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
