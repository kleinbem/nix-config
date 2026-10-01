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
  # pcscd is socket-activated and idle-exits after ~60s (`-x`), so every
  # YubiKey use after a pause is a fresh *start*. core.nix's fleet default
  # (DefaultStartLimitBurst=5 per 15m, meant for crash loops) trips on normal
  # sops/age-plugin-yubikey use — hit 2026-10-01: service and socket both
  # went start-limit-hit and every decrypt failed "Could not open YubiKey"
  # until a manual reset-failed. Exempt it: there's no Restart=, so it can't
  # crash-loop on its own, and the socket's TriggerLimit still caps storms.
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

  boot.initrd.systemd.storePaths = lib.mkIf config.boot.initrd.systemd.enable [
    pkgs.pcsclite.lib
  ];
}
