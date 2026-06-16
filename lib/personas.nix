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

  # --- Uniqueness assertions ---
  # Fail evaluation if a typo creates two personas with identical
  # email, matrix-id, or signing-key file. Each must be globally
  # unique within the manifest.

  _findDuplicates = field:
    let
      values = lib.mapAttrsToList (_: p: p.${field}) identity;
      counts = lib.foldl' (acc: v: acc // { ${v} = (acc.${v} or 0) + 1; }) { } values;
    in
    lib.attrNames (lib.filterAttrs (_: c: c > 1) counts);

  assertUniqueEmails =
    let dups = _findDuplicates "email"; in
    lib.assertMsg (dups == [])
      "duplicate email(s) in personas.nix: ${lib.concatStringsSep ", " dups}";

  assertUniqueMatrixIds =
    let dups = _findDuplicates "matrix-id"; in
    lib.assertMsg (dups == [])
      "duplicate matrix-id(s) in personas.nix: ${lib.concatStringsSep ", " dups}";

  assertUniqueSigningKeys =
    let dups = _findDuplicates "signing-key"; in
    lib.assertMsg (dups == [])
      "duplicate signing-key file(s) in personas.nix: ${lib.concatStringsSep ", " dups}";

  # Composite — call this from any module that depends on the manifest
  # being internally consistent. Fails fast at eval time.
  assertValid =
    assertComplete
    && assertUniqueEmails
    && assertUniqueMatrixIds
    && assertUniqueSigningKeys;

  # --- Rendered views ---

  # Markdown directory page. Generated by `just personas::team`.
  teamMarkdown =
    let
      statusBadge = s: {
        active = "🟢 active";
        probation = "🟡 probation";
        on-leave = "🌴 on leave";
        retired = "⚪ retired";
        purged = "❌ purged";
      }.${s} or s;
      leaveDetail = s:
        if s.status != "on-leave" then "" else
          " — ${s.leave-type or "?"}"
          + (if s.return-date != null then " (back ${s.return-date})" else "");
      renderPersona = name: p:
        let s = p.state; in ''
          ### ${p.full-name}

          | | |
          |---|---|
          | **Status**     | ${statusBadge s.status}${leaveDetail s} |
          | **Since**      | ${s.status-since} |
          | **Origin**     | ${p.origin} (${p.timezone}) |
          | **Joined**     | ${p.date-joined} |
          | **Email**      | `${p.email}` |
          | **Matrix**     | `${p.matrix-id}` |
          | **Tool**       | ${p.tool} (`${p.model}`) |
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

      _Auto-generated from `nix-config/personas.nix` + `personas-state.nix`._
      _Regenerate with `just personas::team`._

      ${lib.concatStrings (lib.mapAttrsToList renderPersona all)}
    '';
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
    assertUniqueEmails
    assertUniqueMatrixIds
    assertUniqueSigningKeys
    assertValid
    teamMarkdown
    names
    all
    ;
}
