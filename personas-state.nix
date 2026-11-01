# Persona lifecycle state, kept apart from personas.nix so frequent status
# changes don't churn the identity file. Edit through the `just personas::*`
# recipes (activate, probation, leave, resume, retire, purge).
# Valid statuses, leave types and transitions: lib/personas.nix.
# backup = the persona covering while this one is on leave (null = none).

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
