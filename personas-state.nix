# Persona lifecycle state, apart from personas.nix so status changes don't
# churn the identity file. Valid values are in lib/personas.nix; return-date,
# leave-type and backup (covering persona, null = none) apply while on leave.

{
  martin = {
    status = "active";
    status-since = "2025-01-01";
    status-note = "";
    return-date = null;
    leave-type = null;
    backup = null; # founder; no human backup
  };

  michael-gruber = {
    status = "active";
    status-since = "2026-06-16";
    status-note = "";
    return-date = null;
    leave-type = null;
    backup = "thomas-schmidt";
  };

  thomas-schmidt = {
    status = "active";
    status-since = "2026-06-16";
    status-note = "";
    return-date = null;
    leave-type = null;
    backup = "michael-gruber";
  };

  daniel-meier = {
    status = "active";
    status-since = "2026-06-16";
    status-note = "";
    return-date = null;
    leave-type = null;
    backup = "michael-gruber";
  };

  rahul-kumar = {
    status = "active";
    status-since = "2026-06-16";
    status-note = "";
    return-date = null;
    leave-type = null;
    backup = null; # CI persona — no human backup needed
  };

  juan-gonzalez = {
    status = "active";
    status-since = "2026-06-16";
    status-note = "";
    return-date = null;
    leave-type = null;
    backup = "daniel-meier";
  };
}
