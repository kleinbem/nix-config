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
      level-zero            # Level Zero API
      ocl-icd               # OpenCL Installable Client Driver
    ];
  };

  environment.sessionVariables = {
    LIBVA_DRIVER_NAME = "iHD";
  };
}