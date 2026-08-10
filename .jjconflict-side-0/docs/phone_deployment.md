# 📱 Nix-on-Droid Deployment: Samsung XCover 6 Pro

## 🧠 Lessons Learned

### 1. The PTY Regression (The "Core" Bug)
*   **Issue:** Newer Nix versions (2.31.3+) attempt to use `TCGETS2` ioctl calls for terminal management. The Android `proot-termux` kernel wrapper does not yet support these, resulting in `Permission denied` errors.
*   **Solution:** Pin the `nix-on-droid` flake input to its own `nixpkgs` (e.g., `release-24.05`). This uses an older, compatible glibc and Nix version that avoids the problematic syscalls.

### 2. Manual Profile Activation
*   **Issue:** Even with the pin, the standard `nix-on-droid switch` script often fails at the final `installPackages` step.
*   **Solution:** Perform a "Manual Atomic Switch". Link the `/nix/var/nix/profiles/nix-on-droid-path` symlink manually and link core binaries (`sh`, `env`) to the new generation's nested `bin` folder.

### 3. Meta-Repo Sync Strategy
*   **Issue:** Local submodules like `nix-presets` aren't easily tracked on the phone.
*   **Solution:** Package the whole meta-workspace as a tarball, push it, and use `--override-input` on the phone.

---

## 🛠️ Automation Suite

### PC Side: `just phone-push`
Uses `scripts/phone-deploy.sh` to:
1. Update locks.
2. Package all 7 repositories + automation scripts.
3. Push to phone `/sdcard/Download/`.

### PC Side: `just phone-backup-fetch`
Downloads the latest `.tar` snapshot from the phone to your PC for safekeeping.

### Phone Side: `bash ~/scripts/phone-activate.sh`
Automates the on-device "hard parts":
1. Initializes Git for all sub-repos.
2. Builds the configuration with local overrides.
3. Swaps the profile symlink and links `/usr/bin/sh`.

### Phone Side: `bash ~/scripts/phone-backup.sh`
Creates a safety snapshot of `/nix` and `/home` (excluding recursive loops).

---

## 🚑 Emergency Recovery (Fail-safe)

If the app fails to boot with a `proot error: /usr/bin/sh not found`:

1.  **Enter Fail-safe:** Long-press the Nix-on-Droid app icon -> select **Fail-safe**.
2.  **Repair Symlinks:** Run:
    ```bash
    ln -sfn /nix/var/nix/profiles/nix-on-droid-path/nix-on-droid-path/bin/sh /data/data/com.termux.nix/files/usr/bin/sh
    ```
3.  **Restart:** Force-stop and start normally.

---

## 🛡️ Backup & Restore

### Backup
Run `bash ~/scripts/phone-backup.sh` on the phone. It creates a `.tar` snapshot of `/nix` and `/home` in your `Download` folder.
