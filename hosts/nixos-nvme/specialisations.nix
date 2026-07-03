{ lib, ... }:

let
  # ---------------------------------------------------------
  # Profile Fragments (Reusable Components)
  # ---------------------------------------------------------

  # Productivity & Development
  workProfile = {
    my.containers = {
      code-server.enable = lib.mkForce true;
      authelia.enable = lib.mkForce false;
      github-runner.enable = lib.mkForce false;
    };
  };

  # Full AI & Service Suite
  playgroundProfile = {
    environment.etc."specialisation".text = lib.mkForce "playground";
    my.containers = {
      code-server.enable = lib.mkForce true;
      # n8n.enable = lib.mkForce true;
      # qdrant = {
      #   enable = lib.mkForce true;
      #   ip = lib.mkForce "10.85.46.105/24";
      # };
      # monitoring = {
      #   enable = lib.mkForce true;
      #   ip = lib.mkForce "10.85.46.114/24";
      # };
      # netdata.enable = lib.mkForce true;
      authelia.enable = lib.mkForce false;
      # litellm.enable = lib.mkForce true;
      # playground.enable = lib.mkForce true;
      # comfyui.enable = lib.mkForce true;
      # langflow.enable = lib.mkForce true;
      # langfuse.enable = lib.mkForce true;
      # agent-team = {
      #   enable = lib.mkForce true;
      #   ip = lib.mkForce "10.85.46.113/24";
      # };
      # ollama.enable = lib.mkForce true;
      github-runner.enable = lib.mkForce false;
    };
  };

  # Common fixes for specialisations (Persistence assertions)
  commonFixes = {
    fileSystems = {
      "/".neededForBoot = lib.mkForce true;
      "/var".neededForBoot = lib.mkForce true;
      "/var/lib/images".neededForBoot = lib.mkForce true;
      "/nix".neededForBoot = lib.mkForce true;
      "/nix/persist".neededForBoot = lib.mkForce true;
    };
  };

in
lib.recursiveUpdate workProfile {
  specialisation = {
    # --- Standard Profiles ---
    playground.configuration = lib.recursiveUpdate commonFixes playgroundProfile;
    work.configuration = { };
  };
}
