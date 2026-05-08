# zero-trust.nix — Network micro-segmentation for the container bridge.
# Implements a default-deny policy between containers with explicit allow rules
# for known, legitimate traffic flows.
{
  config,
  lib,
  myInventory,
  ...
}:

let
  inv = myInventory.network;
  hostAddr = config.my.network.hostAddress;

  # ─── Allowed East-West Traffic Flows ────────────────────────
  # Each rule = { src, dst, dport, comment }
  # Only these container-to-container flows are permitted.
  allowedFlows = [
    # ─── Caddy → Proxied Services (ingress, uses service ports) ───
    {
      src = inv.nodes.caddy.ip;
      dst = inv.nodes.dashboard.ip;
      dport = 80;
      comment = "Caddy -> Dashboard";
    }
    {
      src = inv.nodes.caddy.ip;
      dst = inv.nodes.n8n.ip;
      dport = 443;
      comment = "Caddy -> n8n (mTLS)";
    }
    {
      src = inv.nodes.caddy.ip;
      dst = inv.nodes.open-webui.ip;
      dport = 443;
      comment = "Caddy -> Open WebUI (mTLS)";
    }
    {
      src = inv.nodes.caddy.ip;
      dst = inv.nodes.code-server.ip;
      dport = 4444;
      comment = "Caddy -> Code Server";
    }
    {
      src = inv.nodes.caddy.ip;
      dst = inv.nodes.qdrant.ip;
      dport = 443;
      comment = "Caddy -> Qdrant (mTLS)";
    }
    {
      src = inv.nodes.caddy.ip;
      dst = inv.nodes.comfyui.ip;
      dport = 8188;
      comment = "Caddy -> ComfyUI";
    }
    {
      src = inv.nodes.caddy.ip;
      dst = inv.nodes.langflow.ip;
      dport = 7860;
      comment = "Caddy -> Langflow";
    }
    {
      src = inv.nodes.caddy.ip;
      dst = inv.nodes.langfuse.ip;
      dport = 3000;
      comment = "Caddy -> Langfuse";
    }
    {
      src = inv.nodes.caddy.ip;
      dst = inv.nodes.vllm.ip;
      dport = 8000;
      comment = "Caddy -> vLLM";
    }
    {
      src = inv.nodes.caddy.ip;
      dst = inv.nodes.litellm.ip;
      dport = 443;
      comment = "Caddy -> LiteLLM (mTLS)";
    }

    # ─── AI Apps → LiteLLM Gateway (mTLS proxy or direct) ──────
    {
      src = inv.nodes.open-webui.ip;
      dst = inv.nodes.litellm.ip;
      dport = 443;
      comment = "Open WebUI -> LiteLLM (mTLS)";
    }
    {
      src = inv.nodes.agent-zero.ip;
      dst = inv.nodes.litellm.ip;
      dport = 443;
      comment = "Agent Zero -> LiteLLM (mTLS)";
    }
    {
      src = inv.nodes.n8n.ip;
      dst = inv.nodes.litellm.ip;
      dport = 443;
      comment = "n8n -> LiteLLM (mTLS)";
    }

    # ─── Gateway → vLLM Backend (internal) ────────────────────
    {
      src = inv.nodes.litellm.ip;
      dst = inv.nodes.vllm.ip;
      dport = 443;
      comment = "LiteLLM -> vLLM (mTLS)";
    }

    # ─── East-West mTLS Flows (all via port 443) ──────────────
    {
      src = inv.nodes.open-webui.ip;
      dst = inv.nodes.vllm.ip;
      dport = 443;
      comment = "Open WebUI -> vLLM (Direct Failover)";
    }
    {
      src = inv.nodes.open-webui.ip;
      dst = inv.nodes.langfuse.ip;
      dport = 443;
      comment = "Open WebUI -> Langfuse (mTLS)";
    }
    {
      src = inv.nodes.agent-zero.ip;
      dst = inv.nodes.vllm.ip;
      dport = 443;
      comment = "Agent Zero -> vLLM (Direct Failover)";
    }
    {
      src = inv.nodes.n8n.ip;
      dst = inv.nodes.vllm.ip;
      dport = 443;
      comment = "n8n -> vLLM (Direct Failover)";
    }
    {
      src = inv.nodes.n8n.ip;
      dst = inv.nodes.qdrant.ip;
      dport = 443;
      comment = "n8n -> Qdrant (mTLS)";
    }
    # ─── Monitoring & Logging ───────────────────────────────
    {
      src = inv.nodes.monitoring.ip;
      dst = inv.nodes.vllm.ip;
      dport = 8000;
      comment = "Monitoring -> vLLM Metrics";
    }
    {
      src = inv.nodes.monitoring.ip;
      dst = inv.subnet;
      dport = 9100;
      comment = "Monitoring -> All Node Exporters";
    }
    {
      src = inv.subnet;
      dst = inv.nodes.loki.ip;
      dport = 3100;
      comment = "All Containers -> Loki Logging";
    }
    # ─── Security & Identity ────────────────────────────────
    {
      src = inv.nodes.caddy.ip;
      dst = inv.nodes.authelia.ip;
      dport = 9091;
      comment = "Caddy -> Authelia (SSO Subrequests)";
    }
  ];

  # Generate nftables rules from the flow list
  mkAllowRule =
    flow:
    "    ip saddr ${flow.src} ip daddr ${flow.dst} tcp dport ${toString flow.dport} accept comment \"${flow.comment}\"";

  allowRules = lib.concatMapStringsSep "\n" mkAllowRule allowedFlows;

in
{
  # ─── Host-level nftables bridge filtering ───────────────────
  # These rules run ON THE HOST and filter traffic forwarded between
  # container veth interfaces on the bridge. Containers themselves
  # don't need any configuration changes.
  networking.nftables.tables.zero-trust-bridge = {
    family = "inet";
    content = ''
        chain forward {
          type filter hook forward priority filter; policy accept;

          # Only apply to bridge traffic (container subnet)
          ip saddr != ${inv.subnet} accept
          ip daddr != ${inv.subnet} accept

          # --- Always allow: established/related connections ---
          ct state established,related accept

          # --- Always allow: container -> host (DNS, Avahi, etc) ---
          ip daddr ${hostAddr} accept comment "Containers -> Host (DNS, services)"

          # --- Always allow: host -> containers (management) ---
          ip saddr ${hostAddr} accept comment "Host -> Containers (management)"

          # --- Explicitly allowed east-west flows ---
      ${allowRules}

          # --- Default deny: container-to-container ---
          ip saddr ${inv.subnet} ip daddr ${inv.subnet} log prefix "ZT-DENY: " drop comment "Zero Trust: deny unlisted flows"
        }
    '';
  };
}
