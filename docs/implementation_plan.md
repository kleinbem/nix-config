# Setup Fingerprint Reader

## Goal Description

Enable the **Kensington VeriMark Desktop Fingerprint Key (047d:00f2)** for:

1. **Login**: Unlocking the system.
2. **Sudo**: Authorizing administrative commands.

## User Review Required

- [ ] **Enrollment**: You will need to physically touch the reader when prompted.
- [ ] **Sudo Behavior**: Decide if fingerprint should be sufficient for sudo (default: yes).

## Proposed Changes

### System Configuration

#### [/] [MODIFY] [hosts/nixos-nvme/default.nix](file:///home/martin/Develop/github.com/kleinbem/nix-config/hosts/nixos-nvme/default.nix)

- Enable `services.fprintd.enable = true`.
- (Optional) Enable `services.fprintd.tod.enable = true` if standard driver fails.

#### [MODIFY] [users/martin/home.nix](file:///home/martin/Develop/github.com/kleinbem/nix-config/users/martin/home.nix)

- None required (system-level feature).

## Verification Plan

### Manual Verification

1. **Enrollment**: Run `fprintd-enroll`.
2. **Verification**: Run `fprintd-verify`.
3. **Sudo Test**: Open a new terminal and run `sudo -k` then `sudo ls`. It should ask for fingerprint.
