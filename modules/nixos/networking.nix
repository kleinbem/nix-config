{
  config,
  lib,
  pkgs,
  ...
}:

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

  # Automated NetBird joining (Securely using SOPS)
  systemd.services.netbird-autojoin =
    lib.mkIf (config.services.netbird.enable && config.sops.secrets ? netbird_setup_key)
      {
        description = "Automatically join NetBird network";
        after = [
          "netbird.service"
          "sops-install-secrets.service"
        ];
        requires = [ "netbird.service" ];
        wantedBy = [ "multi-user.target" ];

        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };

        script = ''
          # Wait a moment for the daemon to fully settle
          sleep 2
          STATUS=$(${pkgs.netbird}/bin/netbird status 2>&1 || true)
          if echo "$STATUS" | grep -iq "NeedsLogin"; then
            echo "NetBird needs login. Attempting to join with setup key..."
            KEY_PATH="${config.sops.secrets.netbird_setup_key.path}"
            if [ -f "$KEY_PATH" ]; then
              if ! ${pkgs.netbird}/bin/netbird up --setup-key "$(cat "$KEY_PATH")"; then
                echo "Warning: Failed to authenticate NetBird daemon. You may need to manually log in."
              fi
            else
              echo "Error: Setup key file not found at $KEY_PATH"
              exit 1
            fi
          else
            echo "NetBird is already connected or authenticated."
          fi
        '';
      };

  # Ensure Tailscale is disabled as we transition to NetBird
  services.tailscale.enable = false;
}
