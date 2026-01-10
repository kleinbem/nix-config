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
  resource.incus_container.n8n = {
    name = "n8n";
    image = "n8n-image"; # This expects the image to be imported via 'incus image import' manually or via a separate null_resource
    # Ideally, we'd use a resource to import the image too, but incus provider usually expects images to exist.
    # For now, we assume the host has the image (which our deploy script handled, or we can use local file).
    profiles = [ "default" ];

    # Resource Limits
    limits = {
      cpu = "2";
      "memory" = "4GiB";
    };

    # Start container
    running = true;

    # Persistence (Bind Mount)
    device = [
      {
        name = "n8n-data";
        type = "disk";
        properties = {
          source = "/var/lib/n8n";
          path = "/var/lib/n8n";
          shift = "true"; # Magic: Remap IDs so container can write
        };
      }
    ];
  };
}
