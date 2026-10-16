{ pkgs, ... }:

{
  home = {
    packages = with pkgs; [
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

    # scdaemon talks to the YubiKey through pcscd instead of its own CCID
    # driver, so it shares the reader with ykman and friends.
    file.".gnupg/scdaemon.conf".text = ''
      disable-ccid
    '';
    file.".gnupg/common.conf".text = ''
      use-keyboxd
    '';
  };
  services.gpg-agent = {
    enable = true;
    enableSshSupport = false;
    pinentry.package = pkgs.pinentry-gnome3;
  };

}
