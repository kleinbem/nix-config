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
          bind-interfaces = true;

          # Populate nftables set 'ai_whitelisted_ips' in table 'inet ai-airlock'
          # Format: nftset=/<domain>/[<domain>/...]<family>#<table>#<set>
          nftset = map (domain: "/${domain}/4#ai-airlock#ai_whitelisted_ips") allDomains;
        };
      };

    # Ensure dnsmasq waits for the bridge to be ready
    systemd.services.dnsmasq = lib.mkIf config.services.dnsmasq.enable {
      after = [
        "network.target"
        "bridge-${config.my.network.bridge}.service"
      ];
      requires = [ "bridge-${config.my.network.bridge}.service" ];
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

    # ─── Pillar 3: Behavioral Auditing ──────────────────────────
    security.audit.rules = [
      # Monitor the AI Model/Data Store
      "-w /var/lib/images -p wa -k ai_storage_mod"

      # Monitor for common "Escape" or exfiltration techniques
      "-a always,exit -F arch=b64 -S ptrace -k process_spying"
      "-a always,exit -F arch=b64 -S process_vm_readv -k process_spying"
      "-a always,exit -F arch=b64 -S process_vm_writev -k process_spying"

      # Monitor sensitive secrets being accessed by unexpected users
      "-w /var/lib/sops -p r -k sops_read"
    ];

    # ─── Kernel Parameter Tightening ────────────────────────────
    boot.kernel.sysctl = {
      # Disable unprivileged user namespaces unless needed (AI often needs them for sandboxing)
      # "kernel.unprivileged_userns_clone" = 0; # Keeping at 1 as AI tools often use them.

      # Restrict kernel pointer access further
      "kernel.perf_event_paranoid" = lib.mkForce 3;
    };
  };
}
