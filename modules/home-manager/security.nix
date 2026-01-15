{ pkgs, ... }:

{
  home.packages = with pkgs; [
    # -- Password Management --
    keepassxc # Offline Password Manager
    rbw # Bitwarden CLI (Unofficial)
    pinentry-gnome3 # GPG/SSH Pin Entry

    # -- Hardware Tokens (YubiKey) --
    yubikey-manager # CLI Tool (Essential for scripts/backend)
    yubioath-flutter # Modern GUI (Replaces yubikey-manager-qt)
    seahorse # Gnome Keyring Manager (and SSH Askpass provider)
    ssh-to-age
  ];

  systemd.user.sessionVariables = {
    SSH_AUTH_SOCK = "/run/user/1000/ssh-agent";
    SSH_ASKPASS = "${pkgs.lxqt.lxqt-openssh-askpass}/bin/lxqt-openssh-askpass";
  };
}
