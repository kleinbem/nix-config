# 🏗️ System Reference (Auto-generated)


> [!IMPORTANT]
> This file contains the "ground truth" for the current NixOS infrastructure.
> AI assistants MUST read this file at the start of any configuration task.

## 📦 Core Revisions


## 🖥️ Managed Hosts

- **core-gateway** (`192.168.1.1`, openwrt) — physical, gateway, core
- **core-pi** (`10.0.0.22`, aarch64-linux, ssh) — raspberry-pi, central
- **hass-pi** (`10.0.0.21`, aarch64-linux, ssh) — raspberry-pi, home-assistant
- **mesh-node** (`192.168.1.2`, openwrt) — physical, mesh, ap, lxc-host
- **mesh-node-2** (`192.168.1.6`, openwrt) — physical, mesh
- **nasbook** (`192.168.1.30`, x86_64-linux, ssh) — nas, storage, hub
- **net-brain** (`192.168.1.5`, aarch64-linux, ssh) — router, lxc, brain
- **nixos-nvme** (`10.85.46.1`, x86_64-linux, local) — workstation, desktop
- **orin-nano** (`10.0.0.12`, aarch64-linux, ssh) — edge, ai, jetson
- **phone** (`no-ip`, aarch64-linux, local) — mobile, android
- **router-1** (`192.168.1.3`, aarch64-linux, ssh) — router, lxc
- **router-2** (`192.168.1.4`, aarch64-linux, ssh) — router, lxc

## 📡 Network Services (by host)

### container-factory

- 👥 **AI Agent Team** (`agent-team`) `10.85.47.118:8000` — Enterprise Role-Based Agent Team (CrewAI). [AIRLOCK: Restricted Egress] _[src: nix-presets/containers/agent-team.nix:15]_
- 🕵️ **Agent Zero** (`agent-zero`) `10.85.48.113:50001` — Autonomous AI agent framework. [AIRLOCK: Restricted Egress] _[src: nix-presets/containers/agent-zero.nix:14]_
- 🧠 **AnythingLLM** (`anythingllm`) `10.85.48.132:3001` — All-in-one AI workspace and document orchestrator. _[src: nix-presets/containers/anythingllm.nix:12]_
- 📦 **Attic Binary Cache** (`attic`) `10.85.46.120:8080` → `cache.kleinbem.dev` — Nix binary cache server. _[src: nix-presets/containers/attic.nix:13]_
- 🔐 **Authelia SSO** (`authelia`) `10.85.46.123:9091` — Single Sign-On & 2FA. _[src: nix-presets/containers/authelia.nix:14]_
- 💾 **Restic Backup** (`backup`) `10.85.47.128` — Daily system backup container. _[src: nix-presets/containers/backup.nix:12]_
- 🔄 **Caddy Proxy** (`caddy`) `10.85.46.107` — Reverse Proxy & SSL Termination. _[src: nix-presets/containers/caddy/default.nix:18]_
- 💻 **Code Server** (`code-server`) `10.85.46.101:4444` → `code.kleinbem.dev` — VS Code IDE in a hardened core container. _[src: nix-presets/containers/code-server.nix:14]_
- 🎨 **ComfyUI** (`comfyui`) `10.85.46.108:8188` — Advanced Visual Generation. [AIRLOCK: Restricted Egress] _[src: nix-presets/containers/comfyui.nix:12]_
- 🛡️ **CrowdSec LAPI** (`crowdsec`) `10.85.46.119:8080` — Intrusion detection & IP reputation engine. _[src: nix-presets/containers/crowdsec.nix:13]_
- 🖨️ **CUPS Printing** (`cups`) `10.85.46.124:631` — Print server management (Containerized). _[src: nix-presets/containers/cups.nix:12]_
- 🏠 **Dashboard** (`dashboard`) `10.85.46.103:80` → `home.kleinbem.dev` — Homelab Landing Page. _[src: nix-presets/containers/dashboard/options.nix:6]_
- 📹 **Frigate NVR** (`frigate`) `10.85.46.130:5000` — NVR with AI object detection (NVIDIA TensorRT). _[src: nix-presets/containers/frigate.nix:12]_
- 🏃 **GitHub Runner** (`github-runner`) `10.85.46.126` — Isolated CI/CD Runner. _[src: nix-presets/containers/github-runner.nix:42]_
- 🏠 **Home Assistant** (`home-assistant`) `10.85.49.10:8123` — Smart Home Automation. _[src: nix-presets/containers/home-assistant.nix:12]_
- 🌊 **Langflow** (`langflow`) `10.85.46.109:7860` — Visual AI Agent Designer. [AIRLOCK: Restricted Egress] _[src: nix-presets/containers/langflow.nix:12]_
- 👁️ **Langfuse** (`langfuse`) `10.85.46.110:3000` — LLM telemetry and tracing. [AIRLOCK: Restricted Egress] _[src: nix-presets/containers/langfuse.nix:13]_
- 🔌 **LiteLLM Gateway** (`litellm`) `10.85.46.115:4000` — Unified AI API Gateway & Proxy. [AIRLOCK: Restricted Egress] _[src: nix-presets/containers/litellm.nix:13]_
- 📦 **llama-cpp** (`llama-cpp`) _[src: nix-presets/containers/llama-cpp.nix:20]_
- 📜 **Loki Logging** (`loki`) `10.85.47.116:3100` — Centralized Log Aggregator. _[src: nix-presets/containers/loki.nix:13]_
- 📊 **Monitoring** (`monitoring`) `10.85.47.114:3000` — VictoriaMetrics + Grafana Stack. _[src: nix-presets/containers/monitoring.nix:13]_
- 📡 **n8n Automation** (`n8n`) `10.85.46.99:5678` → `n8n.kleinbem.dev` — Workflow automation engine. _[src: nix-presets/containers/n8n.nix:13]_
- 📊 **Netdata** (`netdata`) `10.85.46.122:19999` — Real-time per-second telemetry. _[src: nix-presets/containers/netdata.nix:13]_
- 🦙 **Ollama** (`ollama`) `10.85.46.125:11434` — Native Ollama Inference Engine. _[src: nix-presets/containers/ollama.nix:13]_
- 🤖 **Open WebUI** (`open-webui`) `10.85.48.102:8080` → `chat.kleinbem.dev` — AI Chat interface via Ollama. _[src: nix-presets/containers/open-webui.nix:14]_
- 🐾 **OpenClaw** (`openclaw`) `10.85.48.112` — Dedicated agent framework. _[src: nix-presets/containers/openclaw.nix:14]_
- 📄 **Paperless-ngx** (`paperless`) `10.85.47.131:28981` — Document management system with OCR. _[src: nix-presets/containers/paperless.nix:12]_
- 🎡 **Playground** (`playground`) `10.85.46.106` — Dev sandbox (Shell/SSH Access Only). _[src: nix-presets/containers/playground.nix:14]_
- 🗄️ **Qdrant DB** (`qdrant`) `10.85.47.105:6333` — Vector database for AI context. _[src: nix-presets/containers/qdrant.nix:13]_
- 🔄 **Syncthing (Zotac)** (`syncthing`) `10.85.46.127:8384` — File synchronization for the Main Workstation. _[src: nix-presets/containers/syncthing.nix:12]_
- 📦 **vllm** (`vllm`) _[src: nix-presets/containers/vllm.nix:12]_

### core-pi

- 🖨️ **CUPS Printing** (`cups`) `10.85.46.124:631` — Print server management (Containerized). _[src: nix-presets/containers/cups.nix:12]_
- 🏠 **Dashboard** (`dashboard`) `10.85.46.103:80` → `home.kleinbem.dev` — Homelab Landing Page. _[src: nix-presets/containers/dashboard/options.nix:6]_

### hass-pi

- 🏠 **Home Assistant** (`home-assistant`) `10.85.49.10:8123` — Smart Home Automation. _[src: nix-presets/containers/home-assistant.nix:12]_

### nasbook

- 👥 **AI Agent Team** (`agent-team`) `10.85.47.118:8000` — Enterprise Role-Based Agent Team (CrewAI). [AIRLOCK: Restricted Egress] _[src: nix-presets/containers/agent-team.nix:15]_
- 💾 **Restic Backup** (`backup`) `10.85.47.128` — Daily system backup container. _[src: nix-presets/containers/backup.nix:12]_
- 📜 **Loki Logging** (`loki`) `10.85.47.116:3100` — Centralized Log Aggregator. _[src: nix-presets/containers/loki.nix:13]_
- 📊 **Monitoring** (`monitoring`) `10.85.47.114:3000` — VictoriaMetrics + Grafana Stack. _[src: nix-presets/containers/monitoring.nix:13]_
- 📄 **Paperless-ngx** (`paperless`) `10.85.47.131:28981` — Document management system with OCR. _[src: nix-presets/containers/paperless.nix:12]_
- 🗄️ **Qdrant DB** (`qdrant`) `10.85.47.105:6333` — Vector database for AI context. _[src: nix-presets/containers/qdrant.nix:13]_
- 🔄 **Syncthing (Zotac)** (`syncthing`) `10.85.46.127:8384` — File synchronization for the Main Workstation. _[src: nix-presets/containers/syncthing.nix:12]_

### nixos-nvme

- 🔄 **Caddy Proxy** (`caddy`) `10.85.46.107` — Reverse Proxy & SSL Termination. _[src: nix-presets/containers/caddy/default.nix:18]_
- 🛡️ **CrowdSec LAPI** (`crowdsec`) `10.85.46.119:8080` — Intrusion detection & IP reputation engine. _[src: nix-presets/containers/crowdsec.nix:13]_
- 🖨️ **CUPS Printing** (`cups`) `10.85.46.124:631` — Print server management (Containerized). _[src: nix-presets/containers/cups.nix:12]_
- 🏠 **Dashboard** (`dashboard`) `10.85.46.103:80` → `home.kleinbem.dev` — Homelab Landing Page. _[src: nix-presets/containers/dashboard/options.nix:6]_
- 📊 **Monitoring** (`monitoring`) `10.85.47.114:3000` — VictoriaMetrics + Grafana Stack. _[src: nix-presets/containers/monitoring.nix:13]_
- 🔄 **Syncthing (Zotac)** (`syncthing`) `10.85.46.127:8384` — File synchronization for the Main Workstation. _[src: nix-presets/containers/syncthing.nix:12]_

### orin-nano

- 📹 **Frigate NVR** (`frigate`) `10.85.46.130:5000` — NVR with AI object detection (NVIDIA TensorRT). _[src: nix-presets/containers/frigate.nix:12]_
- 🔄 **Syncthing (Zotac)** (`syncthing`) `10.85.46.127:8384` — File synchronization for the Main Workstation. _[src: nix-presets/containers/syncthing.nix:12]_

### Declared but not currently enabled on any host

- `alertmanager` — Alertmanager
- `authentik` _[src: nix-presets/containers/authentik.nix:13]_
- `common` _[src: nix-presets/containers/common.nix:1]_
- `garage` — Garage S3
- `nextcloud` _[src: nix-presets/containers/nextcloud.nix:14]_
- `odoo` _[src: nix-presets/containers/odoo.nix:14]_
- `ollama-orin` — Ollama Orin Nano
- `ollama-rpi` — Ollama RPi 5
- `stalwart` _[src: nix-presets/containers/stalwart.nix:23]_
- `standalone` _[src: nix-presets/containers/common.nix:3]_
- `syncthing-orin` — Syncthing (Orin)

## 🛠️ Workspace Status

- **Devenv**: Not found in path
- **Autonomous Guardian**: Inactive ❌

## 📜 Open Decisions (ADRs)

- **001-structure-modules-users.md** (`unknown`) — _[src: .agent/decisions/001-structure-modules-users.md]_

## 🤖 AI Capabilities (MCP Tools)
