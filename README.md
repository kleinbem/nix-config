# ❄️ AI-Augmented NixOS Configuration

![NixOS](https://img.shields.io/badge/NixOS-Unstable-blue.svg?style=for-the-badge&logo=nixos&logoColor=white)
![COSMIC](https://img.shields.io/badge/Desktop-COSMIC-purple.svg?style=for-the-badge)
![AI](https://img.shields.io/badge/AI-Ready-green.svg?style=for-the-badge)

A modular, highly-opinionated NixOS configuration built for **AI-assisted development**, **security**, and **performance**.

## ✨ Features

*   **🤖 AI-First Workflow**: Pre-configured with `Ollama` (70B models), `Aider`, and `Gemini CLI`.
*   **🚀 Modern Desktop**: Bleeding-edge **COSMIC DE** with tiling support.
*   **🔒 Secure by Design**:
    *   **Secrets**: Managed via `sops-nix` (encrypted with Age/YubiKey).
    *   **Sandboxing**: Critical apps (Chrome, Obsidian) are isolated using `nixpak`.
*   **⚡ High Performance**: Tuned kernel parameters, massive ZRAM swap, and Intel compute drivers.
*   **🛠️ Developer Experience**: `nix-ld` for binary compatibility, `starship` prompt, and `direnv`.

## 📂 Structure

This repository follows a modular "common + host" pattern:

```tree
.
├── 📂 common/           # Shared configuration modules
│   ├── core.nix         # Base system settings (Nix, Locale, Utils)
│   ├── cosmic.nix       # Desktop Environment & GUI apps
│   ├── intel-compute.nix# Hardware acceleration
│   ├── sandboxing/      # Nixpak wrappers
│   └── users.nix        # User accounts & Security
├── 📂 hosts/            # Machine-specific configurations
│   └── nixos-nvme/      # Primary workstation
└── 📄 flake.nix         # Entry point
```

## 🚀 Quick Start

This project uses `just` as a command runner.

### 1. Enter the Dev Shell
Get all tools (`sops`, `statix`, `deadnix`, `aider`) instantly:
```bash
nix develop
# OR
just dev
```

### 2. Verify Changes
Run linting and tests before applying:
```bash
just lint      # Runs statix & deadnix
just test      # Builds VM to test configuration
```

### 3. Deploy
Apply the configuration to your running system:
```bash
just switch
```

### 4. AI Assistance
Launch the AI Architect (Aider) to edit your config:
```bash
just architect
```

---
*Maintained by [Martin Kleinberger](https://github.com/kleinbem)*
