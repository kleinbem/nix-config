{
  lib,
  pkgs,
  ...
}:

{
  # ==========================================
  # INFRASTRUCTURE HARDENING (Lynis Suggestions)
  # ==========================================

  # Traditional process accounting is not a standard service in NixOS.
  # We implement it manually using the 'acct' package.
  environment.systemPackages = [ pkgs.acct ];

  systemd.services.acct = {
    description = "Process Accounting";
    wantedBy = [ "multi-user.target" ];
    after = [ "local-fs.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.acct}/bin/accton /var/account/pacct";
      ExecStop = "${pkgs.acct}/bin/accton off";
    };
  };

  systemd.tmpfiles.rules = [
    "d /var/account 0700 root root - -"
    "f /var/account/pacct 0600 root root - -"
  ];

  # BANN-7126: Add a legal banner to login
  # This warns that access is for authorized users only.
  services.getty.greetingLine = lib.mkForce "Authorized Access Only. All activity is logged and monitored.";

  # AUTH-9286: Configure password age limits
  # NixOS handles this via loginDefs.
  security.loginDefs.settings = {
    PASS_MAX_DAYS = 180;
    PASS_MIN_DAYS = 1;
    PASS_WARN_AGE = 7;
  };

  # SSH Hardening (Additional)
  services.openssh.settings = {
    # Lynis SSH-7408: LogLevel (suggestion is VERBOSE)
    LogLevel = "VERBOSE";
  };
}
