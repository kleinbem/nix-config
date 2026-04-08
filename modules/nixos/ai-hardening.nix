{
  config,
  lib,
  ...
}:

let
  cfg = config.my.security.ai-hardening;
in
{
  options.my.security.ai-hardening = {
    enable = lib.mkEnableOption "AI Hardening Suite";
    strictEgress = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable global strict egress filtering for known AI containers.";
    };
    whitelistDomains = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Global list of domains to whitelist. (Auto-collected from containers if using factory)";
    };
  };

  config = lib.mkIf cfg.enable {
    # ─── Pillar 1: Advanced Isolation (MAC) ─────────────────────
    security.apparmor = {
      enable = true;
      # profiles = { ... }; # We can add specific profiles here as needed
    };

    # ─── Pillar 2: Network Airlock (Airlock 2.0) ────────────────
    # We use dnsmasq to dynamically populate an nftables set.
    # We aggregate global whitelist domains + per-container whitelist domains.
    services.dnsmasq =
      let
        # Collect all whitelistDomains from containers defined in config.my.containers
        containerDomains = lib.flatten (
          lib.mapAttrsToList (_name: containerCfg: containerCfg.tls.whitelistDomains or [ ]) (
            config.my.containers or { }
          )
        );
        allDomains = lib.unique (cfg.whitelistDomains ++ containerDomains);
      in
      lib.mkIf (cfg.strictEgress && allDomains != [ ]) {
        enable = true;
        settings = {
          # Listen on localhost and the bridge interface for container DNS
          interface = [
            "lo"
            config.my.network.bridge
          ];
          bind-dynamic = true;

          # Populate nftables set 'ai_whitelisted_ips' in table 'inet ai-airlock'
          # Format: nftset=/<domain>/[<domain>/...]<family>#<table>#<set>
          nftset = map (domain: "/${domain}/4#ai-airlock#ai_whitelisted_ips") allDomains;

          # Hardened DNS Resolution: Don't read /etc/resolv.conf (avoid loops)
          # Use explicit privacy-focused upstreams
          no-resolv = true;
          server = [
            "1.1.1.1" # Cloudflare
            "8.8.8.8" # Google
            "9.9.9.9" # Quad9
          ];
        };
      };

    # Ensure dnsmasq waits for the bridge to be ready
    systemd.services.dnsmasq = lib.mkIf config.services.dnsmasq.enable {
      after = [
        "network.target"
        "network-addresses-${config.my.network.bridge}.service"
        "cbr0-netdev.service"
      ];
      requires = [ "cbr0-netdev.service" ];
    };

    networking.nftables.tables.ai-airlock = lib.mkIf cfg.strictEgress {
      family = "inet";
      content = ''
        set ai_whitelisted_ips {
          type ipv4_addr
          flags dynamic, timeout
          timeout 1h
        }

        chain forward {
          type filter hook forward priority filter; policy accept;
          
          # Allow traffic to dynamically whitelisted IPs
          ip daddr @ai_whitelisted_ips accept comment "Airlock 2.0: Dynamic Whitelist"

          # Block egress from AI subnet to internet (anything not local)
          ip saddr 10.85.46.0/24 oifname "eth0" log prefix "AI-AIRLOCK-EXT-DENY: " drop
          
          # Allow local container-to-container if already established
          ct state { established, related } accept
        }
      '';
    };

    # Ensure containers use the Host as their primary DNS server
    # (assuming they are on the 10.85.46.0/24 bridge)
    # The host is usually .1

    # ─── Kernel Parameter Tightening ────────────────────────────
    boot.kernel.sysctl = {
      # Disable unprivileged user namespaces unless needed (AI often needs them for sandboxing)
      # "kernel.unprivileged_userns_clone" = 0; # Keeping at 1 as AI tools often use them.
    };
  };
}
