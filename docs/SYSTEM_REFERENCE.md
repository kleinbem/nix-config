# 🏗️ System Reference (Auto-generated)
*Last Updated: 2026-06-17T18:48:08Z*

> [!IMPORTANT]
> This file contains the "ground truth" for the current NixOS infrastructure.
> Antigravity MUST read this file at the start of any configuration task.

## 📦 Core Revisions
- **nixpkgs**: [`e8be573b417f3daa3dd4cb9052178f848e0c9d1d`](https://github.com/NixOS/nixpkgs/commit/e8be573b417f3daa3dd4cb9052178f848e0c9d1d)
- **home-manager**: `7b1d382faf603b6d264f58627330f9faa5cba149`
- **sops-nix**: `200081c15c55ff8f1d4c780620d350cad79e22c2`

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

## 📡 Network Services
- 👥 **AI Agent Team** (`agent-team`) — `10.85.47.118:8000` — Enterprise Role-Based Agent Team (CrewAI). [AIRLOCK: Restricted Egress]
- 🕵️ **Agent Zero** (`agent-zero`) — `10.85.48.113:50001` — Autonomous AI agent framework. [AIRLOCK: Restricted Egress]
- 🧠 **AnythingLLM** (`anythingllm`) — `10.85.48.132:3001` — All-in-one AI workspace and document orchestrator.
- 🔌 **LiteLLM Gateway** (`litellm`) — `10.85.46.115:4000` — Unified AI API Gateway & Proxy. [AIRLOCK: Restricted Egress]
- 🦙 **Ollama** (`ollama`) — `10.85.46.125:11434` — Native Ollama Inference Engine.
- 🦙 **Ollama Orin Nano** (`ollama-orin`) — `10.85.46.104:11434` — NVIDIA CUDA-accelerated Ollama inference.
- 🦙 **Ollama RPi 5** (`ollama-rpi`) — `10.85.46.117:11434` — CPU-only Ollama inference (ARM64).
- 🤖 **Open WebUI** (`open-webui`) — `10.85.48.102:8080` → `chat.kleinbem.dev` — AI Chat interface via Ollama.
- 🗄️ **Qdrant DB** (`qdrant`) — `10.85.47.105:6333` — Vector database for AI context.
- 🎨 **ComfyUI** (`comfyui`) — `10.85.46.108:8188` — Advanced Visual Generation. [AIRLOCK: Restricted Egress]
- 🌊 **Langflow** (`langflow`) — `10.85.46.109:7860` — Visual AI Agent Designer. [AIRLOCK: Restricted Egress]
- 👁️ **Langfuse** (`langfuse`) — `10.85.46.110:3000` — LLM telemetry and tracing. [AIRLOCK: Restricted Egress]
- 🐾 **OpenClaw** (`openclaw`) — `10.85.48.112` — Dedicated agent framework.
- 🏠 **Home Assistant** (`home-assistant`) — `10.85.49.10:8123` — Smart Home Automation.
- 📡 **n8n Automation** (`n8n`) — `10.85.46.99:5678` → `n8n.kleinbem.dev` — Workflow automation engine.
- 💻 **Code Server** (`code-server`) — `10.85.46.101:4444` → `code.kleinbem.dev` — VS Code IDE in a hardened core container.
- 🏃 **GitHub Runner** (`github-runner`) — `10.85.46.126` — Isolated CI/CD Runner.
- 🎡 **Playground** (`playground`) — `10.85.46.106` — Dev sandbox (Shell/SSH Access Only).
- 📄 **Paperless-ngx** (`paperless`) — `10.85.47.131:28981` — Document management system with OCR.
- 🔐 **Authelia SSO** (`authelia`) — `10.85.46.123:9091` — Single Sign-On & 2FA.
- 🔔 **Alertmanager** (`alertmanager`) — `10.85.47.114:9093` — Alert Routing & Management.
- 📦 **Attic Binary Cache** (`attic`) — `10.85.46.120:8080` → `cache.kleinbem.dev` — Nix binary cache server.
- 💾 **Restic Backup** (`backup`) — `10.85.47.128` — Daily system backup container.
- 🔄 **Caddy Proxy** (`caddy`) — `10.85.46.107` — Reverse Proxy & SSL Termination.
- 🖨️ **CUPS Printing** (`cups`) — `10.85.46.124:631` — Print server management (Containerized).
- 🏠 **Dashboard** (`dashboard`) — `10.85.46.103:80` → `home.kleinbem.dev` — Homelab Landing Page.
- 📜 **Loki Logging** (`loki`) — `10.85.47.116:3100` — Centralized Log Aggregator.
- 📊 **Monitoring** (`monitoring`) — `10.85.47.114:3000` — VictoriaMetrics + Grafana Stack.
- 📊 **Netdata** (`netdata`) — `10.85.46.122:19999` — Real-time per-second telemetry.
- 🔄 **Syncthing (Zotac)** (`syncthing`) — `10.85.46.127:8384` — File synchronization for the Main Workstation.
- 🔄 **Syncthing (Orin)** (`syncthing-orin`) — `10.85.46.129:8384` — File synchronization for the AI Node.
- 🛡️ **CrowdSec LAPI** (`crowdsec`) — `10.85.46.119:8080` — Intrusion detection & IP reputation engine.
- 📹 **Frigate NVR** (`frigate`) — `10.85.46.130:5000` — NVR with AI object detection (NVIDIA TensorRT).

## 🛠️ Workspace Status
- **Devenv**: Available
- **Autonomous Guardian**: Inactive ❌

## 🤖 AI Capabilities (MCP Tools)
- **netbird_status** — Check the status of the NetBird mesh network and connected peers.
- **syncthing_status** — Check Syncthing synchronization status.
- **firefox_search** — Search Firefox history for a keyword in a specific profile (standard, laboratory, temp).
- **get_tool_help** — Run --help on a local binary to see exact usage and flags.
- **check_ai_stack_health** — Check health of containers and secrets on a specific host.
- **get_fleet_status** — Check connectivity and status of all hosts in the inventory using Colmena/NetBird.
- **list_skills** — List all available agent workflows (skills) in the workspace.
- **is_task_running** — Check if a long-running workspace task (like apply or build) is currently active.
- **get_inventory_summary** — Get full inventory of hosts and network nodes.
- **run_just_recipe** — Run a just recipe from the workspace.
- **update_todo** — Add or update a task in TODO.md.
- **distill_knowledge** — Create a new Knowledge Item (KI) in the workspace.
- **analyze_logs** — Fetch and analyze recent logs using ai-logs.py.
- **semantic_search** — Search the Obsidian vault using semantic similarity (embeddings).
- **manage_ai_services** — Manage local AI services (ollama, vllm).
- **get_security_audit_summary** — Read and summarize the latest Lynis security audit report.
- **reindex_vault** — Run the semantic indexer to refresh the vault index.
- **get_system_telemetry** — Fetch real-time hardware telemetry (CPU, Mem, Disk, Temp).
- **get_calendar_events** — Fetch upcoming events from Google Calendar.
- **get_hardware_profile** — Fetch advanced hardware profile, including GPU and Jetson-specific stats.
- **search_paperless** — Search for documents in Paperless-ngx matching a query.
- **get_paperless_document** — Get the full details and OCR text content of a Paperless document.
- **troubleshoot_unit** — Deep troubleshoot a systemd unit by correlating logs with knowledge base.
- **analyze_nix_closure** — Calculate closure size and dependency count for a Nix attribute.
- **checkpoint_workspace_state** — Save a snapshot of the current project state for context recovery.
- **get_workspace_state** — Retrieve the last saved workspace state.
- **check_binary_cache** — Check if a package is available in the Nix binary cache.
- **manage_skill_progress** — Manage progress through a workspace skill.
- **send_notification** — Send a desktop notification.
