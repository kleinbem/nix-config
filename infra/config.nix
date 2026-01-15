_:

{
  # Terraform Backend (Local state for now)
  terraform.backend.local.path = "terraform.tfstate";

  # Providers
  terraform.required_providers = {
    incus = {
      source = "lxc/incus";
      # version = "0.1.0"; # Use latest
    };
  };

  provider.incus = {
    # Defaults to local socket, or configure remotes here
    # generate_client_certificates = true;
    # accept_remote_certificate = true;
  };

  # Resources
  resource.incus_instance.n8n = {
    name = "n8n";
    image = "n8n-image"; # This expects the image to be imported via 'incus image import' manually or via a separate null_resource
    # Ideally, we'd use a resource to import the image too, but incus provider usually expects images to exist.
    # For now, we assume the host has the image (which our deploy script handled, or we can use local file).
    profiles = [ "default" ];

    # Instance Configuration (Limits & Security)
    config = {
      "limits.cpu" = "2";
      "limits.memory" = "4GiB";
      "security.nesting" = "true";
      "boot.autostart" = "true";
    };

    # Start container
    running = true;

    # Persistence (Bind Mount)
    device = [
      {
        name = "root";
        type = "disk";
        properties = {
          pool = "default";
          path = "/";
        };
      }
      {
        name = "n8n-data";
        type = "disk";
        properties = {
          source = "/var/lib/n8n";
          path = "/var/lib/n8n";
          shift = "true"; # Magic: Remap IDs so container can write
        };
      }
      {
        name = "n8n-web";
        type = "proxy";
        properties = {
          listen = "tcp:0.0.0.0:5678";
          connect = "tcp:127.0.0.1:5678";
        };
      }
    ];
  };

  resource.incus_instance.open_webui = {
    name = "open-webui";
    image = "open-webui-image";
    profiles = [ "default" ];

    config = {
      "limits.cpu" = "4"; # AI UI can be heavy
      "limits.memory" = "4GiB";
      "security.nesting" = "true";
      "boot.autostart" = "true";
    };

    running = true;

    device = [
      {
        name = "root";
        type = "disk";
        properties = {
          pool = "default";
          path = "/";
        };
      }
      {
        name = "webui-data";
        type = "disk";
        properties = {
          source = "/var/lib/open-webui";
          path = "/var/lib/open-webui";
          shift = "true";
        };
      }
      {
        name = "webui-proxy";
        type = "proxy";
        properties = {
          listen = "tcp:0.0.0.0:3000";
          connect = "tcp:127.0.0.1:3000";
        };
      }
    ];
  };
}
