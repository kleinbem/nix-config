{
  pkgs,
  ...
}:

{
  imports = [
    ../incus-hardware.nix
  ];

  networking.hostName = "n8n";
  networking.firewall.enable = false; # Container is behind host NAT/Bridge usually

  # Minimal environment
  environment.systemPackages = [
    pkgs.jq
    pkgs.curl
  ];

  services.n8n = {
    enable = true;
    # Using default package for now.
    # If stable is needed, we need to pass the overlay in flake.nix generator config.
    openFirewall = true;
    environment = {
      N8N_LISTEN_ADDRESS = "0.0.0.0";
      N8N_PORT = "5678";
      N8N_PROTOCOL = "http";
      # Secrets handling would go here, user needs to inject n8n_password manually or via environment
    };
  };

  # Fix: Disable DynamicUser to prevent migration of /var/lib/n8n (which is a bind mount)
  systemd.services.n8n.serviceConfig.DynamicUser = pkgs.lib.mkForce false;

  # Disable documentation to save space
  documentation.enable = false;
  documentation.nixos.enable = false;

  system.stateVersion = "25.11";
}
