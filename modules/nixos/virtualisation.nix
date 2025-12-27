{ pkgs, ... }:

{
  # ==========================================
  # VIRTUALIZATION
  # ==========================================
  virtualisation = {
    libvirtd = {
      enable = true;
      onBoot = "ignore";
    };
    podman = {
      enable = true;
      dockerCompat = true;
      defaultNetwork.settings.dns_enabled = true;
    };
  };

  # Virtualization Tools
  environment.systemPackages = with pkgs; [
    podman
    podman-tui
    docker-compose
  ];
}
