# Kernel attack-surface baseline for every host (imported via core.nix).
#
# security/hardening.nix is the big-tier layer (nix-mineral, AppArmor,
# accounting) and only nixos-nvme and orin-nano import it. The Lynis
# sysctls and the module blacklist are cheap and arch-neutral, so they
# belong to the fleet: the Pis, nasbook and mac-mini front the same
# networks and ran stock values until now.
#
# Priority 950, between nix-mineral (900) and mkDefault (1000): nixpkgs'
# own config/sysctl.nix and virtualisation modules set some of these keys
# with mkDefault to a weaker value (kptr_restrict = 1, for one), and two
# definitions at the same priority with different values are a conflict,
# not an override. nix-mineral sets the same values as strings, so it wins
# where it runs without changing anything; a plain host definition
# (priority 100) wins over both.
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
