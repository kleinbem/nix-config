{ pkgs, ... }:

{
  hardware.graphics = {
    enable = true;
    enable32Bit = true;
    extraPackages = with pkgs; [
      intel-media-driver
      libva-vdpau-driver
      libvdpau-va-gl

      # --- AI/Compute Drivers for Intel iGPU ---
      intel-compute-runtime # OpenCL for Intel
      level-zero # Level Zero API
      ocl-icd # OpenCL Installable Client Driver
      vpl-gpu-rt # Media Driver for 12th/13th Gen+ (formerly onevpl-intel-gpu)
    ];
  };

  # Thermal Management
  services.thermald.enable = true;

  environment.sessionVariables = {
    LIBVA_DRIVER_NAME = "iHD";
  };
}
