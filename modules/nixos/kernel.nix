{ lib, ... }:

{
  # ==========================================
  # KERNEL OPTIMIZATIONS & PERFORMANCE
  # ==========================================
  boot = {
    # Network: Enable TCP BBR for superior throughput
    kernelModules = [ "tcp_bbr" ];

    kernel.sysctl = {
      # BBR + Fair Queuing (fq)
      "net.core.default_qdisc" = "fq";
      "net.ipv4.tcp_congestion_control" = "bbr";

      # Memory: Optimize for 64GB RAM
      "vm.swappiness" = lib.mkDefault 10;
      "vm.vfs_cache_pressure" = lib.mkDefault 50;
      "vm.dirty_ratio" = 10;
      "vm.dirty_background_ratio" = 5;

      # Performance & Stability
      "kernel.nmi_watchdog" = 0; # Power/Latency (mobile-first)
      "vm.transparent_hugepage.enabled" = "madvise"; # Avoid bloat, allow high-perf opt-in
    };

    kernelParams = [
      "intel_pstate=active" # Explicitly use Intel's active power management
      "transparent_hugepage=madvise"
      "nvme_load_type=1" # Faster NVMe initialization

      # Graphics & Power
      "i915.enable_psr=0"
      "i915.enable_guc=3" # Enable GuC/HuC for 12th/13th Gen Intel (Stability)
      "snd_hda_intel.power_save=0"
      "snd_hda_intel.power_save_controller=N"

      # Kernel parameters moved to kernel.nix for consolidation
      # Security & Auditing
      "quiet"
      "loglevel=3" # Standard error/warning level
      "systemd.show_status=auto" # Only show failures during boot
      "rd.udev.log_level=3" # Standard udev logging
      "acpi_osi=Linux"
      "pci=noaer" # Suppress PCIe Advanced Error Reporting noise
      "audit=0" # Disable kernel auditing to resolve audit_log_subj_ctx errors
    ];

    # Early KMS: Professional flicker-free boot for Intel i915
    initrd.kernelModules = [ "i915" ];

    # Support for system analysis and crash dumps (Cockpit)
    crashDump.enable = true;
  };

  # Additional Hardware support (Power/Perf)
  services.power-profiles-daemon.enable = lib.mkDefault true;
}
