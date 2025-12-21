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
  ];

  # Optional: Alias for convenience
  programs.bash.shellAliases = {
    scan = "nmap -sC -sV -oN nmap.txt";
  };
}
