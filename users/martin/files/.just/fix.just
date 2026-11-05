# `os fix::*` — quick fixes for known recurring issues.

# Fix YubiKey/Smartcard issues (restart pcscd & agents).
yubikey:
    pkill lxqt-openssh-askpass || true
    gpgconf --kill gpg-agent || true
    sudo systemctl restart pcscd

# Fix Chrome — restart Chrome + YubiKey agents.
# Leaves gnome-shell alone: on Wayland, killing it ends the whole session.
chrome:
    pkill -f google-chrome || true
    just --justfile "{{source_file()}}" yubikey
    google-chrome-stable > /dev/null 2>&1 &
