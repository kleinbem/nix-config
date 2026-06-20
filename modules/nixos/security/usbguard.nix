_: {
  services.usbguard = {
    enable = true;
    rules = ''
      # --- Host Controllers & Hubs (always needed) ---
      allow with-interface equals { 09:00:00 }

      # --- Input Devices ---
      # Dell KB216 Wired Keyboard
      allow id 413c:2113
      # Logitech USB Receiver (wireless mouse/keyboard)
      allow id 046d:c548

      # --- Security Keys ---
      # Trust all Yubico devices (YubiKeys in any interface mode: OTP/FIDO/CCID)
      allow id 1050:*
      # VeriMark DT Fingerprint Key
      allow id 047d:00f2

      # --- Peripherals ---
      # Trust all SanDisk Corp. devices (Flash drives, SD readers)
      allow id 0781:*
      # Intel Bluetooth Adapter
      allow id 8087:0026
      # USB to SATA/PCIe Bridge (External Harddisk Reader)
      allow id 152d:0581
      # Generic USB2.0 Card Reader
      allow id 0bda:0153
      # ESS Technology USB DAC (Audio)
      allow id 0495:3048
      # Trust all GN Audio / Jabra devices (Speak 710, Link 370 dongle, headsets, …)
      allow id 0b0e:*
      # USB 2.0 Hub
      allow id 05e3:0610
      # Terminus Technology Hubs (Nested in VIA units)
      allow id 1a40:0101
      allow id 1a40:0801
      # VIA Labs USB Hub (3.0 and 2.0 components)
      allow id 2109:0817
      allow id 2109:2817
      # Hub Internal Components (SD Reader & Ethernet)
      allow id 2537:1081
      allow id 0bda:8151
      # HD Camera
      allow id 0408:7090
      # Webcam USB Audio
      allow id 0408:7a10

      # --- Debug & Development ---
      # FTDI FT232R USB UART (USB-to-TTL serial adapter for Jetson serial console)
      allow id 0403:6001

      # --- Mobile Devices ---
      # Trust all Samsung Electronics Co., Ltd devices (MTP, ADB, Download Mode, etc.)
      allow id 04e8:*
      # Trust all Huawei Technologies Co., Ltd. devices (MTP, ADB, MatePad Pro, etc.)
      allow id 12d1:*

      # Block everything else
      reject
    '';
    IPCAllowedUsers = [
      "root"
      "martin"
    ];
  };
}
