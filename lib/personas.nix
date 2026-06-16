# Persona library — joins public identity (personas.nix) with private
# contact data (nix-secrets/personas-contact.nix) and lifecycle state
# (personas-state.nix) into a single queryable view.
#
# Callers pass in an optional `contact` attribute set (typically
# imported from nix-secrets via flake input). Without it, the lib
# returns a public-only view where PII fields render as the literal
# string "(private)" — useful in CI / public eval contexts.
#
# Usage:
#   # With private data:
#   import ./lib/personas.nix {
#     inherit lib;
#     contact = import (inputs.nix-secrets + "/personas-contact.nix");
#   }
#
#   # Public-only:
#   import ./lib/personas.nix { inherit lib; }

{ lib, contact ? { } }:
let
  publicData = import ../personas.nix;
  state = import ../personas-state.nix;
  names = lib.attrNames publicData;

  # Sentinel for missing private fields when nix-secrets isn't available.
  redacted = "(private)";

  # PII fields that come from nix-secrets/personas-contact.nix. When
  # contact is empty (public-only eval), these get the redacted string.
  contactFields = [
    "full-name"
    "email"
    "matrix-id"
    "github-account"
    "oidc-subject"
    "origin"
    "timezone"
    "bio"
  ];

  defaultContact = lib.genAttrs contactFields (_: redacted);

  # Joined view: persona = public ⊕ contact ⊕ state.
  all = lib.mapAttrs
    (name: pub:
      let
        c = contact.${name} or defaultContact;
      in
      pub // c // {
        state = state.${name} or {
          status = "active";
          status-since = pub.date-joined or "1970-01-01";
          status-note = "(state file missing entry; treating as active)";
          return-date = null;
          leave-type = null;
          backup = null;
        };
      })
    publicData;

  # `true` when called with real contact data; `false` when public-only.
  contactAvailable = contact != { };

  # --- Queries ---

  author = name:
    let p = all.${name}; in
    if contactAvailable
    then "${p.full-name} <${p.email}>"
    else throw "lib/personas.nix: author() requires contact data — pass `contact = import inputs.nix-secrets + \"/personas-contact.nix\"`";

  byTag = tag:
    lib.filterAttrs (_: p: lib.elem tag (p.role-tags or [ ])) publicData;

  byKind = wantedKind:
    lib.filterAttrs (_: p: p.kind == wantedKind) publicData;

  humans = byKind "human";
  agents = byKind "agent";

  byStatus = wantedStatus:
    lib.filterAttrs (_: p: p.state.status == wantedStatus) all;

  active = byStatus "active";
  onLeave = byStatus "on-leave";
  retired = byStatus "retired";
  probation = byStatus "probation";

  reachable = lib.filterAttrs
    (_: p: lib.elem p.state.status [ "active" "probation" ])
    all;

  # --- Lifecycle transitions ---

  validStatuses = [ "active" "probation" "on-leave" "retired" "purged" ];
  validKinds = [ "human" "agent" ];
  validLeaveTypes = [ "vacation" "sick" "parental" "sabbatical" "bereavement" "jury-duty" ];

  canTransition = from: to:
    let
      table = {
        active = [ "probation" "on-leave" "retired" ];
        probation = [ "active" "on-leave" "retired" ];
        on-leave = [ "active" "retired" ];
        retired = [ "purged" ];
        purged = [ ];
      };
    in
    lib.elem to (table.${from} or [ ]);

  # --- Signing keys (allowed_signers) ---

  # Render `~/.ssh/allowed_signers` from manifest + a pubkey map.
  # Personas with status retired/purged are excluded.
  allowedSigners = personaPubkeys:
    let
      eligible = lib.filterAttrs
        (_: p: !(lib.elem p.state.status [ "retired" "purged" ]))
        all;
      lines = lib.mapAttrsToList
        (name: p:
          let
            key = personaPubkeys.${name} or null;
            id = if contactAvailable then p.email else "${name}@local";
          in
          lib.optionalString (key != null && key != "") "${id} ${key}"
        )
        eligible;
    in
    lib.concatStringsSep "\n" (lib.filter (s: s != "") lines) + "\n";

  # --- Schema validation ---

  requiredPublicFields = [
    "kind"
    "date-joined"
    "signing-key"
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
      checkPublic = name: p:
        let
          missing = lib.filter (k: !(p ? ${k})) requiredPublicFields;
          kindOk = lib.elem p.kind validKinds;
        in
        lib.assertMsg (missing == [ ])
          "persona '${name}' missing public field(s): ${lib.concatStringsSep ", " missing}"
        && lib.assertMsg kindOk
          "persona '${name}' has invalid kind: ${p.kind}";
      checkState = name: p:
        let
          s = p.state;
          missing = lib.filter (k: !(s ? ${k})) requiredStateFields;
          statusOk = lib.elem s.status validStatuses;
          leaveOk = s.status != "on-leave" || lib.elem (s.leave-type or "") validLeaveTypes;
        in
        lib.assertMsg (missing == [ ]) "persona '${name}' missing state field(s): ${lib.concatStringsSep ", " missing}"
        && lib.assertMsg statusOk "persona '${name}' has invalid status: ${s.status}"
        && lib.assertMsg leaveOk "persona '${name}' status=on-leave requires valid leave-type";
    in
    builtins.all (n: checkPublic n publicData.${n} && checkState n all.${n}) names;

  # --- Uniqueness assertions ---

  _findDuplicates = field: src:
    let
      values = lib.mapAttrsToList (_: p: p.${field} or null) src;
      nonNull = lib.filter (v: v != null) values;
      counts = lib.foldl' (acc: v: acc // { ${v} = (acc.${v} or 0) + 1; }) { } nonNull;
    in
    lib.attrNames (lib.filterAttrs (_: c: c > 1) counts);

  # signing-key uniqueness is checkable on public data alone
  assertUniqueSigningKeys =
    let dups = _findDuplicates "signing-key" publicData; in
    lib.assertMsg (dups == [ ])
      "duplicate signing-key file(s) in personas.nix: ${lib.concatStringsSep ", " dups}";

  # email/matrix-id uniqueness only checkable when contact data is loaded
  assertUniqueEmails =
    if !contactAvailable then true else
    let dups = _findDuplicates "email" contact; in
    lib.assertMsg (dups == [ ])
      "duplicate email(s) in personas-contact.nix: ${lib.concatStringsSep ", " dups}";

  assertUniqueMatrixIds =
    if !contactAvailable then true else
    let dups = _findDuplicates "matrix-id" contact; in
    lib.assertMsg (dups == [ ])
      "duplicate matrix-id(s) in personas-contact.nix: ${lib.concatStringsSep ", " dups}";

  assertValid =
    assertComplete
    && assertUniqueSigningKeys
    && assertUniqueEmails
    && assertUniqueMatrixIds;

  # --- Rendered views ---

  teamMarkdown =
    let
      statusBadge = s: {
        active = "🟢 active";
        probation = "🟡 probation";
        on-leave = "🌴 on leave";
        retired = "⚪ retired";
        purged = "❌ purged";
      }.${s} or s;
      kindBadge = k: {
        human = "👤 human";
        agent = "🤖 agent";
      }.${k} or k;
      leaveDetail = s:
        if s.status != "on-leave" then "" else
          " — ${s.leave-type or "?"}"
          + (if s.return-date != null then " (back ${s.return-date})" else "");
      renderPersona = name: p:
        let s = p.state; in ''
          ### ${p.full-name}

          | | |
          |---|---|
          | **Kind**       | ${kindBadge p.kind} |
          | **Status**     | ${statusBadge s.status}${leaveDetail s} |
          | **Since**      | ${s.status-since} |
          | **Origin**     | ${p.origin} (${p.timezone}) |
          | **Joined**     | ${p.date-joined} |
          | **Email**      | `${p.email}` |
          | **Matrix**     | `${p.matrix-id}` |
          | **Tool**       | ${p.tool}${if p.model != null then " (`${p.model}`)" else ""} |
          | **Active hours** | ${p.active-hours} ${p.timezone} |
          | **Role tags**  | ${lib.concatStringsSep ", " (map (t: "`${t}`") p.role-tags)} |
          | **Backup**     | ${if s.backup == null then "_(none)_" else s.backup} |
          ${lib.optionalString (s.status-note != "") "| **Note**       | ${s.status-note} |"}

          ${p.bio}

          ---

        '';
    in
    ''
      # Team

      _Auto-generated from `nix-config/personas.nix` + private contact data + lifecycle state._
      _Regenerate with `just personas::team`._

      ${if contactAvailable then "" else "**Note**: private contact data not loaded — names/emails show as `(private)`.\n\n"}
      ${lib.concatStrings (lib.mapAttrsToList renderPersona all)}
    '';
in
{
  inherit
    author
    byTag
    byKind
    humans
    agents
    byStatus
    active
    onLeave
    retired
    probation
    reachable
    canTransition
    validStatuses
    validKinds
    validLeaveTypes
    allowedSigners
    assertComplete
    assertUniqueEmails
    assertUniqueMatrixIds
    assertUniqueSigningKeys
    assertValid
    teamMarkdown
    contactAvailable
    names
    all
    ;
}
