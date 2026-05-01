{ lib, ... }:

let
  # ---------------------------------------------------------
  # Profile Fragments (Reusable Components)
  # ---------------------------------------------------------

  # Productivity & Development
  workProfile = {
    my.containers = {
      code-server.enable = lib.mkForce true;
      n8n.enable = lib.mkForce true;
      authelia.enable = lib.mkForce true;
      caddy.enable = lib.mkForce true;
      github-runner.enable = lib.mkForce true;
    };
  };

  # Full AI & Service Suite
  playgroundProfile = {
    my.containers = {
      n8n.enable = lib.mkForce true;
      code-server.enable = lib.mkForce true;
      open-webui.enable = lib.mkForce true;
      qdrant.enable = lib.mkForce true;
      monitoring.enable = lib.mkForce true;
      falco.enable = lib.mkForce true;
      netdata.enable = lib.mkForce true;
      authelia.enable = lib.mkForce true;
      dashboard.enable = lib.mkForce true;
      litellm.enable = lib.mkForce true;
      playground.enable = lib.mkForce true;
      caddy.enable = lib.mkForce true;
      comfyui.enable = lib.mkForce true;
      langflow.enable = lib.mkForce true;
      langfuse.enable = lib.mkForce true;
      agent-team.enable = lib.mkForce true;
      ollama.enable = lib.mkForce true;
      github-runner.enable = lib.mkForce true;
    };
    services.android-desktop-emulator.enable = lib.mkForce true;
  };

  # Android Apps Environment
  # waydroidProfile = {
  #   programs.waydroid-setup.enable = lib.mkForce true;
  # };

  # Security Hardening
  hardenedProfile = {
    nix-mineral.enable = lib.mkForce true;
    services.avahi.enable = lib.mkForce false;
    services.printing.enable = lib.mkForce false;
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

  # Fixes for nix-mineral's hardened bind mounts
  mineralFixes = {
    fileSystems."/var/lib".neededForBoot = lib.mkForce true;
    fileSystems."/etc".neededForBoot = lib.mkForce true;
  };

in
{
  specialisation = {
    # --- Standard Profiles ---
    playground.configuration = lib.recursiveUpdate commonFixes playgroundProfile;
    work.configuration = lib.recursiveUpdate commonFixes workProfile;
    # waydroid.configuration = lib.recursiveUpdate commonFixes waydroidProfile;
    hardened.configuration = lib.recursiveUpdate commonFixes (
      lib.recursiveUpdate mineralFixes hardenedProfile
    );

    # --- Composite Profiles (Combined Modes) ---

    # Combined Work & Waydroid
    # work-waydroid.configuration = lib.recursiveUpdate commonFixes (
    #   lib.recursiveUpdate workProfile waydroidProfile
    # );

    # Combined AI Playground & Waydroid
    # playground-waydroid.configuration = lib.recursiveUpdate commonFixes (
    #   lib.recursiveUpdate playgroundProfile waydroidProfile
    # );

    # Combined Work & Hardening
    work-hardened.configuration = lib.recursiveUpdate commonFixes (
      lib.recursiveUpdate mineralFixes (lib.recursiveUpdate workProfile hardenedProfile)
    );
  };
}
