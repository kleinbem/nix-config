# Open items

- [ ] **Image-based deployment**: atomic images (UKI / `systemd-repart`) instead of `switch`, so every boot is a fresh image.
- [ ] **Fresh-install drill**: install nixos-nvme from the flake onto a blank disk in a VM (`system.build.vmWithDisko`) to check the partition layout and the recovery path.
- [ ] **Restore drill**: restore one host's secure bundle and a restic snapshot from R2 (see [docs/BACKUP-RECOVERY.md](docs/BACKUP-RECOVERY.md)).
- [ ] **systemd-homed**: encrypt the home directory with the YubiKey (FIDO2), which would also fix the keyring login.
- [ ] **Face login**: evaluate `howdy`, now packaged in nixpkgs.
