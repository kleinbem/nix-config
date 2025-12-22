{ pkgs, ... }:

{
  home.packages = with pkgs; [
    # --- Reconnaissance ---
    nmap
    subfinder # Subdomain discovery
    httpx # HTTP probing
    nuclei # Template-based vulnerability scanner (Essential for Bug Bounty)
    whois
    dig

    # --- Web Auditing ---
    burpsuite # The gold standard proxy
    zap # OWASP ZAP (Open Source alternative to Burp)
    ffuf # Fast Web Fuzzer
    gobuster # Directory/DNS buster

    # --- Network Analysis ---
    wireshark
    mitmproxy # CLI proxy (Scriptable with Python)

    # --- Exploitation / Brute Force ---
    thc-hydra
    sqlmap
    metasploit

    # --- AI Agent / Analysis ---
    fabric-ai # Pipe tool output to AI patterns (e.g. | fabric -p analyze_nmap)

    # --- Wordlists ---
    seclists

    # --- Advanced Recon ---
    katana # Next-gen crawling and spidering
    feroxbuster # Recursive content discovery (Rust)
    gitleaks # Secret scanning for git repos

    # --- Mobile / Reverse Engineering ---
    apktool
    jadx

    # --- Automation Scripts ---
    (pkgs.writeShellScriptBin "ai-hunt" ''
      target=$1
      if [ -z "$target" ]; then
        echo "Usage: ai-hunt <domain>"
        exit 1
      fi

      echo "🤖 AI-Hunter initiated on $target..."
      mkdir -p "$HOME/Develop/hunting/$target"
      out="$HOME/Develop/hunting/$target"

      echo "[1/4] 🔍 Enumerating Subdomains..."
      ${pkgs.subfinder}/bin/subfinder -d "$target" -silent > "$out/subs.txt"

      echo "[2/4] 🌐 Probing Alive Hosts..."
      cat "$out/subs.txt" | ${pkgs.httpx}/bin/httpx -silent > "$out/alive.txt"

      echo "[3/4] 💥 Running Nuclei Scans..."
      ${pkgs.nuclei}/bin/nuclei -l "$out/alive.txt" -o "$out/vulns.txt" -silent

      echo "[4/4] 🧠 Fabric AI Analysis..."
      if [ -s "$out/vulns.txt" ]; then
        # Pipe findings to AI for risk assessment
        cat "$out/vulns.txt" | fabric --pattern analyze_security_report
        echo "✅ Analysis Complete. Report saved to $out"
      else
        echo "✅ No obvious vulnerabilities found to analyze."
      fi
    '')
  ];

  # Optional: Alias for convenience
  programs.bash.shellAliases = {
    scan = "nmap -sC -sV -oN nmap.txt";
    # Easy access to seclists
    wordlists = "cd $WORDLISTS";
  };

  # Export the Seclists path for tools like ffuf/gobuster
  home.sessionVariables = {
    WORDLISTS = "${pkgs.seclists}/share/wordlists";
  };
}
