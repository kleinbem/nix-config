{ lib, ... }:

{
  # ==========================================
  # KERNEL OPTIMIZATIONS & PERFORMANCE
  # ==========================================
  boot = {
    # Network: Enable TCP BBR for superior throughput
    kernelModules = [ "tcp_bbr" ];

    # Blacklist insecure network protocols (Lynis Suggestion NETW-3200)
    blacklistedKernelModules = [
      "dccp"
      "sctp"
      "rds"
      "tipc"
      "pcspkr" # Also from security.nix
    ];
    kernel.sysctl = {
      # BBR + Fair Queuing (fq)
      "net.core.default_qdisc" = "fq";
      "net.ipv4.tcp_congestion_control" = "bbr";

      # Performance & Stability
      "kernel.nmi_watchdog" = 1; # Enabled to detect and recover from hard hangs
      "vm.transparent_hugepage.enabled" = "madvise"; # Avoid bloat, allow high-perf opt-in

      # Memory: Optimize for ZRAM and High-Load AI Caching
      "vm.swappiness" = lib.mkDefault 100;
      "vm.vfs_cache_pressure" = lib.mkDefault 50;
      "vm.dirty_ratio" = 5; # Reduced from 10 to flush I/O sooner (better for i3-1315U)
      "vm.dirty_background_ratio" = 2; # Reduced from 5

      # ==========================================
      # KERNEL HARDENING (Lynis Suggestions)
      # ==========================================
      "kernel.sysrq" = 4; # Allow only sync-unmount-reboot
      "kernel.kptr_restrict" = 2; # Hide kernel pointers
      "kernel.unprivileged_bpf_disabled" = 1; # Restrict BPF to root (prevents many Spectre-class attacks)
      "kernel.dmesg_restrict" = 1; # Restrict dmesg access to root
      "kernel.randomize_va_space" = 2; # Full ASLR
      "net.core.bpf_jit_harden" = 2; # Harden BPF JIT compiler
      "vm.unprivileged_userfaultfd" = 0; # Restrict userfaultfd to root

      # Network Protocol Hardening
      "net.ipv4.conf.all.rp_filter" = 1;
      "net.ipv4.conf.default.rp_filter" = 1;
      "net.ipv4.conf.all.accept_redirects" = 0;
      "net.ipv4.conf.default.accept_redirects" = 0;
      "net.ipv6.conf.all.accept_redirects" = 0;
      "net.ipv6.conf.default.accept_redirects" = 0;
      "net.ipv4.conf.all.log_martians" = 1;
      "net.ipv4.conf.default.log_martians" = 1;
      "net.ipv4.conf.all.send_redirects" = 0;
      "net.ipv4.conf.default.send_redirects" = 0;
    };

    kernelParams = [
      "intel_pstate=active" # Explicitly use Intel's active power management
      "transparent_hugepage=madvise"
      "nvme_load_type=1" # Faster NVMe initialization
      "nvme_core.default_ps_max_latency_us=5500" # WD SN740 Stability Fix (Middle Ground)

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
      "audit=1" # Enabled to support auditd events
    ];

    # Early KMS: Professional flicker-free boot for Intel i915
    initrd.kernelModules = [ "i915" ];

    # Support for system analysis and crash dumps (Cockpit)
    crashDump.enable = true;
  };

  # Thermald is vastly superior for Intel chips handling sustained AI thermal load
  services.thermald.enable = lib.mkDefault true;
  services.power-profiles-daemon.enable = lib.mkForce false; # Disable to prevent conflicts
}
