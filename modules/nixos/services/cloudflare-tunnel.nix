{
  config,
  ...
}:

{
  services.cloudflared = {
    enable = true;
    tunnels = {
      "nixos-nvme" = {
        credentialsFile = config.sops.templates."cloudflare-tunnel-credentials.json".path;
        originRequest = {
          noTLSVerify = true;
        };
        ingress = {
          "home.kleinbem.dev" = "https://10.85.46.107:443";
          "chat.kleinbem.dev" = "https://10.85.46.107:443";
          "code.kleinbem.dev" = "https://10.85.46.107:443";
          "n8n.kleinbem.dev" = "https://10.85.46.107:443";
          "cache.kleinbem.dev" = "https://10.85.46.107:443";
        };
        default = "http_status:404";
      };
    };
  };
}
