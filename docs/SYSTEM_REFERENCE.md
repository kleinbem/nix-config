# 🏗️ System Reference (Auto-generated)


> [!IMPORTANT]
> This file contains the "ground truth" for the current NixOS infrastructure.
> AI assistants MUST read this file at the start of any configuration task.

## 📦 Core Revisions


## 🖥️ Managed Hosts

- **ap-upstairs** (`10.0.0.2`, openwrt) — physical, ap
- **core-gateway** (`10.0.0.1`, openwrt) — physical, gateway, core
- **core-pi** (`10.0.0.22`, aarch64-linux, ssh) — raspberry-pi, central
- **hass-pi** (`10.0.0.21`, aarch64-linux, ssh) — raspberry-pi, home-assistant
- **mac-mini** (`10.0.0.16`, x86_64-linux, ssh) — desktop, legacy-hardware
- **nasbook** (`10.0.0.30`, x86_64-linux, ssh) — nas, storage, hub
- **nixos-nvme** (`10.85.46.1`, x86_64-linux, local) — workstation, desktop
- **orin-nano** (`10.0.0.15`, aarch64-linux, ssh) — edge, ai, jetson
- **phone** (`no-ip`, aarch64-linux, local) — mobile, android
- **tablet** (`no-ip`, aarch64-linux, local) — mobile, android

## 📡 Network Services (by host)

### Declared but not currently enabled on any host

- `alertmanager` — Alertmanager
- `comfyui` — ComfyUI
- `ente-web` — Ente Auth Web
- `garage` — Garage S3
- `github-runner` — GitHub Runner
- `langflow` — Langflow
- `langfuse` — Langfuse
- `langgraph` — LangGraph
- `litellm` — LiteLLM Gateway
- `n8n` — n8n Automation
- `ollama` — Ollama
- `ollama-orin` — Ollama Orin Nano
- `playground` — Playground
- `syncthing-orin` — Syncthing (Orin)

## 🤖 AI Capabilities (MCP Tools)
