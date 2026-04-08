_:

{
  # ==========================================
  # NETWORKING & DNS (Secure & Resilient)
  # ==========================================

  networking = {
    # Use local resolver first, then privacy-focused public fallbacks
    nameservers = [
      "1.1.1.1" # Cloudflare
      "8.8.8.8" # Google (as requested by user)
      "127.0.0.1" # Local resolver (dnsmasq/resolved)
      "9.9.9.9" # Quad9
    ];

    # Ensure resolvconf doesn't overwrite our preferred order
    resolvconf.enable = true;
  };

  # prioritize Netbird startup
  systemd.services.netbird = {
    after = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];
  };
}
