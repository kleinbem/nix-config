_:

{
  services.homepage-dashboard = {
    enable = true;
    listenPort = 8082;
    openFirewall = true;
  };

  # Allow dashboard to access Docker socket
  systemd.services.homepage-dashboard.serviceConfig.SupplementaryGroups = [ "docker" ];

  services.homepage-dashboard = {
    # Custom Background (requires image to be in valid location, usually /var/lib/homepage-dashboard/images or via extraOptions)
    # NixOS module writes config to /etc/homepage-dashboard/settings.yaml and mounts it.
    settings = {
      background = {
        image = "background.png";
      };
      layout = {
        "System" = {
          style = "row";
          columns = 4;
        };
        "Automation" = {
          style = "row";
          columns = 2;
        };
        "Development" = {
          style = "row";
          columns = 4;
        };
        "AI" = {
          style = "row";
          columns = 2;
        };
      };
    };

    # Top-level Widgets
    widgets = [
      {
        search = {
          provider = "google";
          target = "_blank";
          url = "https://google.ie";
        };
      }
      {
        openmeteo = {
          label = "Watergrasshill";
          latitude = 52.02;
          longitude = -8.34;
          timezone = "Europe/Dublin";
          units = "metric";
        };
      }
      {
        resources = {
          cpu = true;
          memory = true;
          disk = "/";
        };
      }
      {
        docker = {
          socket = "/var/run/docker.sock";
          containers = [
            "homepage"
            "n8n"
            "ollama" # If containerized
            "open-webui" # If containerized
          ];
        };
      }
      {
        datetime = {
          format = {
            date = "dddd, MMMM Do YYYY";
            time = "HH:mm";
          };
        };
      }
    ];

    # Service Discovery & Widgets
    services = [
      {
        "System" = [
          {
            "Cockpit" = {
              href = "http://localhost:9091";
              description = "System Management";
              icon = "cockpit.png";
            };
          }
          {
            "Incus" = {
              href = "https://localhost:8443";
              description = "System Containers";
              icon = "incus.png";
            };
          }
          {
            "CUPS" = {
              href = "http://localhost:631";
              description = "Printer Management";
              icon = "cups.png";
            };
          }
        ];
      }
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
        "Development" = [
          {
            "Code Server" = {
              href = "http://localhost:4444";
              description = "VS Code Web";
              icon = "vscode.png";
            };
          }
          {
            "SilverBullet" = {
              href = "http://localhost:3333";
              description = "Notes & Knowledge Base";
              icon = "silverbullet.png";
            };
          }
        ];
      }
      {
        "AI" = [
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
              # Widget removed to prevent error until upstream fix or config verification
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
