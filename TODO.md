# Project Roadmap 🗺️

## Security Enhancements
- [ ] **Secure Boot**: Implement `lanzaboote` to cryptographically sign the NixOS kernel and bootloader.
- [ ] **YubiKey LUKS**: Bind disk encryption directly to YubiKey (Slot 2) for "Touch to Decrypt" boot.

## Architecture
- [ ] **Image-Based Deployment**: Transition from `nixos-rebuild switch` to atomic Image deployment (UKI / `systemd-repart`).
    - *Goal*: Truly immutable system state where every boot is a fresh image.
- [ ] **Disko Verification**:
    - [ ] Run `nix run github:nix-community/disko -- --mode test ./common/disko-config.nix` in a VM to verify partition logic.
    - [ ] Test "Dormant Recovery" plan (format blank disk -> install from flake).
- [ ] **Impermanence ("Erase Your Darlings")**:
    - [ ] Move root `/` to tmpfs (RAM).
    - [ ] Persist only `/nix` and `/persist` via `environment.persistence`.
- [ ] **Maintenance**:
    - [ ] Enable `system.autoUpgrade` for unattended security patches.
    - [ ] Verify `rclone` restore workflow (Simulate data loss).
    - [ ] **Ollama**: Manually run `ollama pull llama3.1:70b-instruct-q4_K_M` (Removed from config to unblock deploy).
