_:

{
  services.homepage-dashboard = {
    enable = true;
    listenPort = 8082;
    openFirewall = true;

    # Service Discovery & Widgets
    services = [
      {
        "Automation" = [
          {
            "n8n" = {
              href = "http://localhost:5678";
              description = "Workflow Automation";
              icon = "n8n.png";
            };
          }
        ];
      }
      {
        "AI" = [
          {
            "Open WebUI" = {
              href = "http://localhost:3000";
              description = "LLM Chat";
              icon = "si-openwebui"; # Standard icon
            };
          }
          {
            "Ollama" = {
              href = "http://localhost:11434";
              description = "LLM Backend";
              icon = "ollama.png";
              widget = {
                type = "ollama";
                url = "http://localhost:11434";
              };
            };
          }
        ];
      }
    ];

    # Bookmarks (External Links)
    bookmarks = [
      {
        "Developer" = [
          {
            "GitHub" = [
              {
                abbr = "GH";
                href = "https://github.com";
              }
            ];
          }
        ];
      }
    ];
  };
}
