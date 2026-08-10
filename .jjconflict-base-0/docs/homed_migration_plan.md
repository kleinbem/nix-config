# Migration Plan: systemd-homed

> [!WARNING]
> This is a **DESTRUCTIVE** migration. You will delete your user account and recreate it.
> **DO NOT** execute this until you have verified backups externally.

## 1. Preparation (The Safety Net)

1. **Backup Data:**
    * Push all Git repos to remote (GitHub).
    * Backup Documents/Images to Google Drive (rclone) or external USB.
    * **Crucial:** Copy your `~/.ssh` and `~/.config/sops` keys to a USB stick. You will need these to decrypt your secrets after recreation!

2. **Create "Rescue" Admin:**
    * You cannot delete `martin` while logged in as `martin`.
    * Add a temporary admin user to your NixOS config:

    ```nix
    # modules/nixos/users.nix
    users.users.rescue = {
      isNormalUser = true;
      extraGroups = [ "wheel" ];
      initialPassword = "password123"; # Change immediately or use hash
    };
    ```

3. **Apply & Test Rescue:**
    * `sudo nixos-rebuild switch --flake .`
    * Log out and **Log in as `rescue`**.
    * Verify `sudo` works for `rescue`.

## 2. The Migration (The Scary Part)

1. **Disable NixOS User Management for Martin:**
    * In `modules/nixos/users.nix`, **remove** or comment out the `users.users.martin` block completely.
    * Enable homed: `services.homed.enable = true;`.
    * Apply: `sudo nixos-rebuild switch --flake .` (This might warn about orphan user, that's fine).

2. **Delete Old User:**
    * `sudo userdel -r martin` (This wipes `/home/martin`).

3. **Create New Homed User:**
    * `homectl create martin --storage=luks --fs-type=btrfs --real-name="Martin Kleinberger" -G wheel --shell=/run/current-system/sw/bin/bash`
    * It will ask for a password. This will be your new **Disk & Login** password.

4. **Enroll YubiKey (The Magic):**
    * `homectl update martin --fido2-device=auto`
    * (Touch your YubiKey).
    * Now your YubiKey unlocks your home folder!

## 3. Restoration

1. **Log in as Martin:**
    * You should now have a fresh, empty home.
2. **Restore Secrets:**
    * Copy SSH keys and SOPS keys back from USB.
3. **Re-run Home Manager:**
    * Since NixOS isn't managing your user anymore, you might need to run Home Manager manually the first time or ensure your standalone Home Manager config takes over.
    * `nix run home-manager/master -- switch --flake .#martin`

## 4. Cleanup

1. Remove `rescue` user from `users.nix`.
