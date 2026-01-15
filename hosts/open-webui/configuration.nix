{
  modulesPath,
  ...
}:

{
  imports = [
    (modulesPath + "/virtualisation/lxc-container.nix")
    ../incus-hardware.nix # Standard Incus Hardware optimizations
  ];

  networking.hostName = "open-webui";

  # --- Open WebUI Service ---
  services.open-webui = {
    enable = true;
    port = 3000;
    host = "0.0.0.0"; # Listen on all interfaces so proxy works
    environment = {
      # Point to the Host's IP (Incus usually maps host.incus or we use the bridge IP)
      # For now, we assume the host is accessible via the gateway.
      # A robust way is to use 'host.lxd' or '10.0.100.1' if statically defined.
      # Defaulting to 10.0.100.1 which is the common incus bridge gateway.
      OLLAMA_BASE_URL = "http://10.0.100.1:11434";

      # Persist data
      DATA_DIR = "/var/lib/open-webui";
    };
  };

  # Open firewall for the proxy
  networking.firewall.allowedTCPPorts = [ 3000 ];

  # State Persistence
  systemd.tmpfiles.rules = [
    "d /var/lib/open-webui 0750 open-webui open-webui - -"
  ];

  system.stateVersion = "24.05";
}
