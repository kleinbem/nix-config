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

    file.".gnupg/common.conf".text = ''
      use-keyboxd
    '';
  };
  programs.gpg = {
    enable = true;
    # scdaemon goes through pcscd and opens the YubiKey shared: an exclusive
    # open makes age-plugin-yubikey (sops) fail with "generic error".
    scdaemonSettings = {
      disable-ccid = true;
      pcsc-shared = true;
    };
  };
  services.gpg-agent = {
    enable = true;
    enableSshSupport = false;
    pinentry.package = pkgs.pinentry-gnome3;
  };

}
