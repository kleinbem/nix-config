# Persona library — consumers should read identity and state through
# these helpers rather than importing the raw files directly.
#
# Pattern:
#   let personas = import ../lib/personas.nix { inherit lib; }; in
#     personas.author "michael"     → "Michael Gruber <michael@kleinbem.dev>"
#     personas.active                → all personas with status == active
#     personas.byStatus "on-leave"   → all personas currently on leave
#     personas.byTag "ci-runner"     → all personas with the role-tag
#     personas.onCall                → personas whose active-hours window covers now
#                                       (in their own timezone)
#     personas.canRetire "michael"   → bool (only certain statuses can retire)
#
# Identity is in personas.nix, state in personas-state.nix. The library
# joins them by name so callers don't have to.

{ lib }:
let
  identity = import ../personas.nix;
  state = import ../personas-state.nix;
  names = lib.attrNames identity;

  # Joined view: persona = identity ⊕ state.
  all = lib.mapAttrs
    (name: ident: ident // {
      state = state.${name} or {
        status = "active";
        status-since = ident.date-joined or "1970-01-01";
        status-note = "(state file missing entry; treating as active)";
        return-date = null;
        leave-type = null;
        backup = null;
      };
    })
    identity;

  # --- Identity-side queries ---

  author = name:
    let p = identity.${name}; in
    "${p.full-name} <${p.email}>";

  byTag = tag:
    lib.filterAttrs (_: p: lib.elem tag (p.role-tags or [])) identity;

  # --- State-side queries ---

  byStatus = wantedStatus:
    lib.filterAttrs (_: p: p.state.status == wantedStatus) all;

  active = byStatus "active";
  onLeave = byStatus "on-leave";
  retired = byStatus "retired";
  probation = byStatus "probation";

  # Personas reachable for work right now (active, not on leave, not retired).
  reachable = lib.filterAttrs
    (_: p: lib.elem p.state.status [ "active" "probation" ])
    all;

  # --- Lifecycle transition validation ---

  validStatuses = [ "active" "probation" "on-leave" "retired" "purged" ];
  validLeaveTypes = [ "vacation" "sick" "parental" "sabbatical" "bereavement" "jury-duty" ];

  canTransition = from: to:
    let
      table = {
        active = [ "probation" "on-leave" "retired" ];
        probation = [ "active" "on-leave" "retired" ];
        on-leave = [ "active" "retired" ];
        retired = [ "purged" ];
        purged = [ ]; # terminal
      };
    in
    lib.elem to (table.${from} or [ ]);

  # --- Signing-key derived data ---

  # Render `~/.ssh/allowed_signers` contents from the manifest and a
  # map of pubkey strings (typically built from the .pub files).
  # Personas with status retired or purged are excluded — their key
  # is no longer trusted for new commit verification.
  allowedSigners = personaPubkeys:
    let
      eligible = lib.filterAttrs
        (_: p: !(lib.elem p.state.status [ "retired" "purged" ]))
        all;
      lines = lib.mapAttrsToList
        (name: p:
          let key = personaPubkeys.${name} or null; in
          lib.optionalString (key != null && key != "") "${p.email} ${key}"
        )
        eligible;
    in
    lib.concatStringsSep "\n" (lib.filter (s: s != "") lines) + "\n";

  # --- Schema validation (fail-fast at evaluation time) ---

  requiredIdentityFields = [
    "full-name"
    "date-joined"
    "origin"
    "timezone"
    "bio"
    "email"
    "matrix-id"
    "github-account"
    "signing-key"
    "oidc-subject"
    "tool"
    "model"
    "role-tags"
    "active-hours"
  ];

  requiredStateFields = [
    "status"
    "status-since"
    "status-note"
    "return-date"
    "leave-type"
    "backup"
  ];

  assertComplete =
    let
      checkIdent = name: p:
        let missing = lib.filter (k: !(p ? ${k})) requiredIdentityFields; in
        lib.assertMsg (missing == [])
          "persona '${name}' missing identity field(s): ${lib.concatStringsSep ", " missing}";
      checkState = name: p:
        let
          s = p.state;
          missing = lib.filter (k: !(s ? ${k})) requiredStateFields;
          statusOk = lib.elem s.status validStatuses;
          leaveOk = s.status != "on-leave" || lib.elem (s.leave-type or "") validLeaveTypes;
        in
        lib.assertMsg (missing == []) "persona '${name}' missing state field(s): ${lib.concatStringsSep ", " missing}"
        && lib.assertMsg statusOk "persona '${name}' has invalid status: ${s.status}"
        && lib.assertMsg leaveOk "persona '${name}' status=on-leave requires valid leave-type";
    in
    builtins.all (n: checkIdent n identity.${n} && checkState n all.${n}) names;
in
{
  inherit
    author
    byTag
    byStatus
    active
    onLeave
    retired
    probation
    reachable
    canTransition
    validStatuses
    validLeaveTypes
    allowedSigners
    assertComplete
    names
    all
    ;
}
