# Kernel attack-surface baseline for every host (imported via core.nix); the
# heavier hardening.nix layer is only on nixos-nvme and orin-nano.
#
# Priority 950, between nix-mineral (900) and mkDefault (1000): nixpkgs sets
# some keys with mkDefault to weaker values, and equal priorities with
# different values conflict. A plain host definition still wins.
{ lib, ... }:
let
  fleet = lib.mkOverride 950;
in
{
  boot = {
    # Lynis NETW-3200 plus the PC speaker. nix-mineral's own module
    # blacklist is off under the compatibility preset, so this list is
    # the fleet's.
    blacklistedKernelModules = [
      "dccp"
      "sctp"
      "rds"
      "tipc"
      "pcspkr"
      "snd_pcsp"
    ];

    kernel.sysctl = {
      "kernel.sysrq" = fleet 4; # sync, unmount, reboot only
      "kernel.kptr_restrict" = fleet 2;
      "kernel.unprivileged_bpf_disabled" = fleet 1;
      "kernel.dmesg_restrict" = fleet 1;
      "kernel.randomize_va_space" = fleet 2;
      "net.core.bpf_jit_harden" = fleet 2;
      "vm.unprivileged_userfaultfd" = fleet 0;
      # Strict reverse-path filtering: nixos-nvme and orin-nano have run it
      # next to the NetBird interface and the cross-host container routes
      # without drops, so the rest of the fleet gets the same.
      "net.ipv4.conf.all.rp_filter" = fleet 1;
      "net.ipv4.conf.default.rp_filter" = fleet 1;
      "net.ipv4.conf.all.accept_redirects" = fleet 0;
      "net.ipv4.conf.default.accept_redirects" = fleet 0;
      "net.ipv6.conf.all.accept_redirects" = fleet 0;
      "net.ipv6.conf.default.accept_redirects" = fleet 0;
      "net.ipv4.conf.all.log_martians" = fleet 1;
      "net.ipv4.conf.default.log_martians" = fleet 1;
      "net.ipv4.conf.all.send_redirects" = fleet 0;
      "net.ipv4.conf.default.send_redirects" = fleet 0;
    };
  };
}
