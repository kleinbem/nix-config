{ myInventory, ... }:
{
  # ==========================================
  # ENTERPRISE AI TEAM AIRLOCK (RBAC)
  # ==========================================
  # These rules enforce 'Least Privilege' at the network level on the host,
  # ensuring that agents can only communicate with approved upstream targets.
  networking.nftables.tables.ai-airlock = {
    family = "inet";
    content = ''
      chain forward {
        type filter hook forward priority filter; policy accept;

        # AI Agent Team -> LiteLLM & Langfuse
        ip saddr ${myInventory.network.nodes.agent-team.ip} ip daddr { ${myInventory.network.nodes.litellm.ip}, ${myInventory.network.nodes.langfuse.ip} } tcp dport { 4000, 3000 } accept
        
        # Bootstrap/Maintenance: Allow DNS and HTTPS temporarily for uv dependency sync
        ip saddr ${myInventory.network.nodes.agent-team.ip} udp dport 53 accept
        ip saddr ${myInventory.network.nodes.agent-team.ip} tcp dport { 53, 443 } accept

        # Block Agent Team from reaching the broader Internet or local network
        ip saddr ${myInventory.network.nodes.agent-team.ip} reject with icmpx type admin-prohibited
      }
    '';
  };
}
