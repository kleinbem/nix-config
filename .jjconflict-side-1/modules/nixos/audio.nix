{
  lib,
  config,
  pkgs,
  ...
}:
let
  cfg = config.my.audio;

  jabraButtonsScript =
    pkgs.writers.writePython3Bin "jabra-buttons"
      {
        libraries = [ pkgs.python3Packages.evdev ];
        flakeIgnore = [ "E501" ];
      }
      ''
        """Dispatch Jabra HID button events to system actions.

        Listens on every input device whose USB vendor id is 0x0b0e (GN Audio /
        Jabra). Volume +/- and the dedicated Mute button are already wired up
        by the kernel + desktop environment; this script handles the otherwise-
        idle HID Telephony buttons (hook switch / Phone Mute / Smart).

        Discover unmapped keys live with:
            journalctl --user -u jabra-buttons -f
        """
        import os
        import selectors
        import subprocess
        import time

        import evdev
        from evdev import ecodes

        JABRA_VENDOR = 0x0b0e
        WPCTL = "${pkgs.wireplumber}/bin/wpctl"


        def run(cmd):
            if cmd:
                subprocess.Popen(cmd, shell=True)


        def toggle_mic_mute():
            run(f"{WPCTL} set-mute @DEFAULT_AUDIO_SOURCE@ toggle")


        def smart_button():
            run(os.environ.get("JABRA_SMART_BUTTON_CMD", ""))


        ACTIONS = {
            ecodes.KEY_PHONE: toggle_mic_mute,        # HID Telephony hook switch
            ecodes.KEY_MICMUTE: toggle_mic_mute,      # HID Telephony Phone Mute
            ecodes.KEY_VOICECOMMAND: smart_button,
            ecodes.KEY_PROG1: smart_button,
        }


        def find_devices():
            out = []
            for path in evdev.list_devices():
                try:
                    d = evdev.InputDevice(path)
                except (OSError, PermissionError):
                    continue
                if d.info.vendor == JABRA_VENDOR:
                    out.append(d)
            return out


        def loop():
            while True:
                devices = find_devices()
                if not devices:
                    time.sleep(2)
                    continue
                sel = selectors.DefaultSelector()
                for d in devices:
                    sel.register(d.fd, selectors.EVENT_READ, d)
                try:
                    while True:
                        for key, _ in sel.select(timeout=10.0):
                            for ev in key.data.read():
                                if ev.type == ecodes.EV_KEY and ev.value == 1:
                                    name = ecodes.keys.get(ev.code, str(ev.code))
                                    print(f"jabra key: {name}", flush=True)
                                    act = ACTIONS.get(ev.code)
                                    if act:
                                        act()
                except OSError:
                    # Device unplugged; rediscover after a brief pause.
                    time.sleep(1)


        if __name__ == "__main__":
            loop()
      '';
in
{
  options.my.audio = {
    jabra = {
      preferred = lib.mkEnableOption ''
        Prefer Jabra audio devices (Speak 710, Link 370, …) as the default
        PipeWire sink/source whenever they are connected. Matches by vendor
        id 0x0b0e, so any current or future Jabra device is covered. WirePlumber
        still honours an explicit user override stored in
        ~/.local/state/wireplumber/default-nodes — clear that file if a manual
        pick is sticking against your wishes.
      '';

      buttons = {
        enable = lib.mkEnableOption ''
          Wire the otherwise-idle Jabra HID call-control buttons (hook
          switch / Phone Mute / Smart) to user-level actions via a systemd
          user service. Volume +/- and the dedicated Mute button are already
          handled by the kernel + desktop environment and are not touched.

          The service auto-discovers any plugged-in Jabra device by vendor
          id and watches /dev/input/event* with seat-owner ACLs (uaccess).
        '';

        smartButtonCommand = lib.mkOption {
          type = lib.types.str;
          default = "";
          example = "playerctl play-pause";
          description = ''
            Shell command executed when the Jabra Smart button fires
            (KEY_VOICECOMMAND / KEY_PROG1 in evdev terms). Leave empty to
            ignore. Runs in the user's environment so D-Bus / GUI tools work.
          '';
        };
      };
    };
  };

  config = lib.mkMerge [
    (lib.mkIf cfg.jabra.preferred {
      services.pipewire.wireplumber.extraConfig."51-jabra-priority" = {
        "monitor.alsa.rules" = [
          {
            matches = [
              { "device.vendor.id" = "0x0b0e"; }
            ];
            actions.update-props = {
              "priority.session" = 2000;
              "priority.driver" = 2000;
            };
          }
        ];
      };
    })

    (lib.mkIf cfg.jabra.buttons.enable {
      # Grant the active session ACL access to Jabra HID input nodes and
      # provide a stable /dev/input/jabra-control symlink (handy for debug).
      services.udev.extraRules = ''
        SUBSYSTEM=="input", ATTRS{idVendor}=="0b0e", TAG+="uaccess", SYMLINK+="input/jabra-control"
      '';

      systemd.user.services.jabra-buttons = {
        description = "Jabra HID call-control button dispatcher";
        wantedBy = [ "default.target" ];
        after = [
          "pipewire.service"
          "wireplumber.service"
        ];
        serviceConfig = {
          ExecStart = "${jabraButtonsScript}/bin/jabra-buttons";
          Restart = "on-failure";
          RestartSec = "5s";
        };
        environment.JABRA_SMART_BUTTON_CMD = cfg.jabra.buttons.smartButtonCommand;
      };
    })
  ];
}
