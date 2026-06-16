# Personas lifecycle state — changes weekly. Kept separate from
# personas.nix (identity, rarely changes) so day-to-day status updates
# don't churn the identity file's history.
#
# Mutated by recipes:
#   just personas::activate NAME
#   just personas::probation NAME
#   just personas::leave NAME TYPE [UNTIL]
#   just personas::resume NAME
#   just personas::retire NAME [REASON]
#   just personas::purge NAME
#
# Schema per persona:
#   status        active | probation | on-leave | retired | purged
#   status-since  ISO date — when this state was entered
#   status-note   Free-text reason (human-readable)
#   return-date   ISO date (null unless on-leave with planned return)
#   leave-type    null | vacation | sick | parental | sabbatical | bereavement | jury-duty
#                 (only meaningful when status = "on-leave")
#   backup        Persona name covering work while this one is on-leave (null = no backup)
#
# State transitions (enforced by recipes):
#   any         → on-leave    (need leave-type)
#   on-leave    → active      (just personas::resume)
#   any         → retired     (graceful end of life)
#   retired     → purged      (rare; GDPR-style erasure)
#   probation   → active      (after first reviewed PR)
#   active      → probation   (only if explicitly demoted)

{
  michael = {
    status = "active";
    status-since = "2026-06-16";
    status-note = "";
    return-date = null;
    leave-type = null;
    backup = "thomas";
  };

  thomas = {
    status = "active";
    status-since = "2026-06-16";
    status-note = "";
    return-date = null;
    leave-type = null;
    backup = "michael";
  };

  daniel = {
    status = "active";
    status-since = "2026-06-16";
    status-note = "";
    return-date = null;
    leave-type = null;
    backup = "michael";
  };

  rahul = {
    status = "active";
    status-since = "2026-06-16";
    status-note = "";
    return-date = null;
    leave-type = null;
    backup = null; # CI persona — no human backup needed
  };

  juan = {
    status = "active";
    status-since = "2026-06-16";
    status-note = "";
    return-date = null;
    leave-type = null;
    backup = "daniel";
  };
}
