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
    # JetPack 6's defconfig left out NFT_CT, NFT_REDIR and NFT_FIB_*. The kernel
    # builds them since kleinbem/nix-hardware#71, but nftables stays off (legacy
    # iptables) until it is tested on the device. no-link: vendor defconfig.
    nftables.enable = false;
    nat = {
      enable = true;
      internalInterfaces = [ "cbr0" ];
      externalInterface = "enP8p1s0";
    };
    firewall = {
      enable = true;
      backend = "iptables";
      package = pkgs.iptables-legacy;
      trustedInterfaces = [ "cbr0" ];
      # SSH and MeshLLM API over NetBird
      interfaces."wt0".allowedTCPPorts = [
        22
        9337
      ];
      # Allow SSH and MeshLLM API on LAN
      interfaces."enP8p1s0".allowedTCPPorts = [
        22
        9337
      ];
    };
  };

  systemd = {
    services.enforce-container-routes.enable = lib.mkForce false;
    timers.enforce-container-routes.enable = lib.mkForce false;
  };
}
