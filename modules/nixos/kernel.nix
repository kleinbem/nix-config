{ lib, pkgs, ... }:
# Kernel performance and hardware tuning for the AI workstation tier.
# Hardening lives in security/hardening.nix.
{
  boot = {
    kernelModules = [ "tcp_bbr" ];

    kernel.sysctl = {
      # BBR with fq pacing, TCP Fast Open both ways.
      "net.core.default_qdisc" = "fq";
      "net.ipv4.tcp_congestion_control" = "bbr";
      "net.ipv4.tcp_fastopen" = 3;

      "kernel.nmi_watchdog" = 1; # recover from hard hangs
      "vm.transparent_hugepage.enabled" = "madvise";

      # Memory: zram-first, MGLRU on, flush dirty pages early.
      "vm.swappiness" = lib.mkDefault 150;
      "vm.vfs_cache_pressure" = lib.mkDefault 50;
      "kernel.mm.lru_gen.enabled" = 7;
      "vm.watermark_boost_factor" = 0;
      "vm.dirty_ratio" = 5;
      "vm.dirty_background_ratio" = 2;
    };

    kernelParams = [
      "intel_pstate=active"
      "transparent_hugepage=madvise"
      "nvme_load_type=1"
      "i915.enable_guc=3" # GuC/HuC on 12th/13th gen Intel
      "snd_hda_intel.power_save=0"
      "snd_hda_intel.power_save_controller=N"
      "quiet"
      "loglevel=3"
      "systemd.show_status=auto"
      "rd.udev.log_level=3"
      "acpi_osi=Linux"
      "audit=1" # auditd events (audit.nix)
    ];

    # Early KMS for i915; the module does not exist in the Tegra kernel.
    initrd.kernelModules = lib.optionals pkgs.stdenv.hostPlatform.isx86 [ "i915" ];

    crashDump.enable = true;
  };

  # thermald does not compile on aarch64.
  services.thermald.enable = lib.mkDefault pkgs.stdenv.hostPlatform.isx86;
  services.power-profiles-daemon.enable = lib.mkForce false; # conflicts with thermald
}
