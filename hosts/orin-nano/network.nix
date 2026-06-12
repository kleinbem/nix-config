{ lib, ... }:
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
              address = "10.0.0.12";
              prefixLength = 16;
            }
          ];
          # Suppress static routes from network-routing.nix — other hosts' container
          # subnets (10.85.47-49.0/24) are not routable from the Orin's 10.0.0.x LAN.
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
    nat = {
      enable = true;
      internalInterfaces = [ "cbr0" ];
      externalInterface = "enP8p1s0";
    };
    firewall = {
      enable = true;
      trustedInterfaces = [ "cbr0" ];
      # SSH only over NetBird — not exposed on LAN
      interfaces."wt0".allowedTCPPorts = [ 22 ];
      # Also allow SSH on LAN for emergency access (e.g. before NetBird is running)
      interfaces."enP8p1s0".allowedTCPPorts = [ 22 ];
      extraForwardRules = ''
        iifname "cbr0" oifname "enP8p1s0" accept
        iifname "enP8p1s0" oifname "cbr0" ct state { established, related } accept
      '';
    };
  };
}
