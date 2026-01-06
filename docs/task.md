# Task: Declarative Migration

- [x] SSH Config (`programs.ssh`) <!-- id: 0 -->
  - [x] Check existing `~/.ssh/config` (None found) <!-- id: 1 -->
  - [x] Enrolled via `pamu2fcfg` alongside YubiKeys.

# Completed Tasks (Shell Migration)

- [x] Migrate `zellij` to `programs.zellij`.
- [x] Migrate `lazygit` to `programs.lazygit`.
  - [x] Implement `programs.ssh` in `dev.nix` <!-- id: 2 -->
  - [x] Verify YubiKey settings <!-- id: 3 -->
- [x] VS Code (`programs.vscode`) <!-- id: 4 -->
  - [x] Create `vscode.nix` module <!-- id: 5 -->
  - [x] Configure extensions <!-- id: 6 -->
- [x] Nixvim Migration (The Big One) <!-- id: 7 -->
  - [x] Add `nixvim` to `flake.nix` inputs <!-- id: 8 -->
  - [x] Create `modules/home-manager/nixvim.nix` <!-- id: 9 -->
  - [x] output `nvim` package <!-- id: 10 -->
