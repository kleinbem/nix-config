{
  pkgs,
  config,
  lib,
  ...
}:
{
  environment.systemPackages = with pkgs; [
    # Smartcard (PKCS#11 PIV)
    opensc
    yubico-piv-tool
    yubikey-manager
  ];

  services.pcscd.enable = true;
  programs.yubikey-touch-detector.enable = true;

  services.gnome = {
    gnome-keyring.enable = true;
    # Disable GNOME's GCR SSH Agent to prevent conflict with programs.ssh
    gcr-ssh-agent.enable = false;
  };

  programs.ssh.agentPKCS11Whitelist = "/nix/store/*,/run/current-system/*";

  security.pam = {
    services = {
      gdm = {
        enableGnomeKeyring = true;
        u2fAuth = true;
      };
      login = {
        enableGnomeKeyring = true;
        u2fAuth = true;
      };
      sudo.u2fAuth = true;
    };
  };

  # U2F / YubiKey Configuration (PAM level)
  security.pam.u2f = {
    enable = true;
    settings = {
      cue = true; # Prompt the user to touch the key
      authfile = config.sops.secrets.u2f_keys.path;
    };
  };

  boot.initrd.systemd.storePaths = lib.mkIf config.boot.initrd.systemd.enable [
    pkgs.pcsclite.lib
  ];
}
