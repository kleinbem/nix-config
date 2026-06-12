let
  flake = builtins.getFlake (toString ./.);
  host = flake.nixosConfigurations.nixos-nvme;
  playground = host.config.specialisation.playground.configuration;
  inherit (playground) options;
in
builtins.length options.containers.type.getSubOptions."ollama".config.definitions
