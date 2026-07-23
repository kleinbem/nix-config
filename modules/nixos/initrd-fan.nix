{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.my.boot.initrd-fan;

  fanScript = pkgs.writeShellScript "initrd-fan-max" ''
    set -u
    export PATH=${
      lib.makeBinPath [
        pkgs.kmod
        pkgs.coreutils
        pkgs.systemd
      ]
    }:$PATH

    # Best-effort: load the PWM controller then the fan driver. No-op if built-in
    # or absent — a missing fan driver must never wedge the boot.
    for m in ${lib.escapeShellArgs cfg.kernelModules}; do
      modprobe "$m" 2>/dev/null || true
    done
    udevadm settle -t 5 2>/dev/null || true

    PWM=${toString cfg.pwm}
    did=0

    # (1) hwmon PWM fans: force manual mode then write the duty value.
    for p in /sys/class/hwmon/hwmon*/pwm1 /sys/class/hwmon/hwmon*/device/pwm1; do
      [ -w "$p" ] || continue
      # pwm1_enable: 1 = manual (some drivers 0 = disable auto). Try to take manual control.
      [ -w "''${p}_enable" ] && echo 1 > "''${p}_enable" 2>/dev/null || true
      if echo "$PWM" > "$p" 2>/dev/null; then
        echo "initrd-fan: $p <- $PWM"
        did=1
      fi
    done

    # (2) thermal cooling-device fans (pwm-fan also registers here): max out cur_state.
    for c in /sys/class/thermal/cooling_device*; do
      t=$(cat "$c/type" 2>/dev/null) || continue
      case "$t" in
        *fan*)
          m=$(cat "$c/max_state" 2>/dev/null) || continue
          if [ -n "$m" ] && [ -w "$c/cur_state" ] && echo "$m" > "$c/cur_state" 2>/dev/null; then
            echo "initrd-fan: $c ($t) cur_state <- $m"
            did=1
          fi
          ;;
      esac
    done

    [ "$did" = 1 ] || echo "initrd-fan: no writable fan node found (driver missing / auto-only) — safe no-op"
    exit 0
  '';
in
{
  options.my.boot.initrd-fan = {
    enable = lib.mkEnableOption ''
      Spin the PWM fan to full speed during the initrd. The userspace fan daemon
      (nvfancontrol on Jetson) only starts once the full system boots, so while
      the machine waits at a LUKS/Tang prompt or drops to an initrd emergency
      shell the fan is uncontrolled and the SoC can heat up. This provides active
      cooling during that pre-OS window; it is a best-effort safety net and never
      blocks boot if the fan driver is missing'';

    pwm = lib.mkOption {
      type = lib.types.ints.between 0 255;
      default = 255;
      description = "PWM duty to write to the fan (0 = off, 255 = full speed).";
    };

    kernelModules = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "pwm-tegra"
        "pwm-fan"
      ];
      description = ''
        Modules the fan needs, loaded (and made available in the initrd) in order:
        the PWM controller first, then the pwm-fan hwmon driver. Defaults suit the
        Jetson Orin. NOTE: on hosts whose `boot.initrd.availableKernelModules` is
        set with `lib.mkOverride`/`mkForce` (e.g. the Orin), this list is clobbered
        there — add the same modules to that host's own list too.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = config.boot.initrd.systemd.enable;
        message = "my.boot.initrd-fan requires boot.initrd.systemd.enable = true (systemd stage-1 initrd).";
      }
    ];

    # Make the fan modules available in the initrd (normal priority; see the
    # kernelModules note above for hosts that mkOverride this list).
    boot.initrd.availableKernelModules = cfg.kernelModules;

    boot.initrd.systemd = {
      storePaths = [ fanScript ];
      services.initrd-fan = {
        description = "Spin PWM fan to full during initrd (pre-OS thermal safety)";
        # Run before the (potentially long) LUKS/Tang unlock wait so the fan is
        # already spinning while the machine sits at a prompt.
        wantedBy = [ "cryptsetup.target" ];
        before = [ "cryptsetup.target" ];
        unitConfig.DefaultDependencies = false;
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = fanScript;
          # Bounded so a wedged modprobe/settle can never hold up cryptsetup.target.
          # It's pulled in via Wants= (wantedBy), so a timeout-failure here does not
          # block the unlock — boot proceeds without the fan kick.
          TimeoutStartSec = 15;
        };
      };
    };
  };
}
