{
  pkgs,
  config,
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
  # pcscd idle-exits after ~60s, so every YubiKey use after a pause is a new
  # start, and core.nix's 5-starts-per-15m default trips on normal sops use
  # ("Could not open YubiKey"). Safe to exempt: no Restart=, and the socket's
  # TriggerLimit still caps storms.
  systemd.services.pcscd.unitConfig.StartLimitIntervalSec = 0;
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

  boot.initrd.systemd.storePaths = [ pkgs.pcsclite.lib ];
}
