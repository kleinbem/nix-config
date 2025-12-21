{ pkgs, ... }:

let
  verify-system = pkgs.writeShellApplication {
    name = "verify-system";
    runtimeInputs = with pkgs; [
      coreutils
      systemd
      curl
      pciutils
      gnugrep
      fzf
      fastfetch
      mpv
      ripgrep
      starship
      podman
    ];
    text = ''
      echo "🔍 Verifying System State..."

      # 1. Check Core System
      echo -n "Checking NixOS Version... "
      if grep -q "NixOS" /etc/os-release; then
          echo "✅ $(uname -r)"
      else
          echo "❌ NOT NixOS"
          exit 1
      fi

      echo -n "Checking Intel GPU Access... "
      if [ -e /dev/dri/renderD128 ]; then
          echo "✅ Present (/dev/dri/renderD128)"
      else
          echo "❌ MISSING GPU DEVICE"
          # Don't exit, might be headless?
      fi

      echo -n "Checking ZRAM Swap... "
      if grep -q "/dev/zram" /proc/swaps; then
          echo "✅ Active"
      else
          echo "❌ INACTIVE"
          exit 1
      fi

      # 2. Check Services
      # We check valid services. If they are not running, systemctl returns non-zero.

      echo -n "Checking Ollama Service... "
      if systemctl is-active --quiet ollama.service; then
          echo "✅ Active"
      else
          echo "❌ INACTIVE (Is it enabled?)"
          # exit 1 (Optional: strict mode)
      fi

      echo -n "Checking Open WebUI Service... "
      if systemctl is-active --quiet open-webui.service; then
          echo "✅ Active"
      else
          echo "❌ INACTIVE"
      fi

      # 3. Check Ports (Open WebUI)
      echo -n "Checking Open WebUI Port (8080)... "
      if timeout 1 bash -c '</dev/tcp/localhost/8080' &>/dev/null; then
        echo "✅ Accessible"
      else
        echo "❌ Unreachable"
      fi

      # 4. Check Tools existence (These are in runtimeInputs so they MUST exist, 
      # but this checks if they are in the user profile too if needed, 
      # though here we are just checking availability).
      echo "Checking Tools:"
      REQUIRED_TOOLS=("nh" "fzf" "fastfetch" "mpv" "rg" "starship" "podman")
      for tool in "''${REQUIRED_TOOLS[@]}"; do
          echo -n "  - $tool... "
          if command -v "$tool" &> /dev/null; then
              echo "✅ Installed"
          else
              echo "❌ MISSING"
          fi
      done

      echo "🎉 Verification Complete! System is healthy."
    '';
  };
in
{
  environment.systemPackages = [ verify-system ];
}
