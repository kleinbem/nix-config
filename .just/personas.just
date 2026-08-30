import 'common.just'

set working-directory := ".."

# --- Persona orchestration ---
#
# Reads from nix-config/personas.nix (the manifest) and orchestrates the
# infrastructure that makes a persona operational: signing key, sops
# secrets, GitHub key registration, Stalwart mailbox.
#
# Add a new persona:
#   1. Edit nix-config/personas.nix and add the attribute block.
#   2. Run: just personas::add <name>
#   3. (One-time per session) Run: just personas::tf-apply
#
# The Stalwart/SES Terraform changes don't run on every add — only when
# DNS/IAM needs updating (rare). Per-persona setup is fast (~30s).

# Both recipes below `import` kleinbem-secrets/personas/contact.nix directly
# — plain Nix since 2026-08-09 (full-name/email/etc. become public the
# moment a persona commits anything, so sops-encrypting them at rest never
# bought real confidentiality; protected by the private repo only now,
# matching the file's own original design intent).
[group("Personas")]
list:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "🎭 Personas declared in personas.nix:"
    CONTACT_PATH="../kleinbem-secrets/personas/contact.nix" nix eval --raw --impure --expr \
        'let
            lib = (import <nixpkgs> {}).lib;
            contactPath = builtins.getEnv "CONTACT_PATH";
            contact = if contactPath != "" then import contactPath else {};
            p = import ./lib/personas.nix { inherit lib contact; };
         in builtins.concatStringsSep "\n" (map (n: "  - " + p.all.${n}."full-name" + " <" + p.all.${n}.email + ">  (" + p.all.${n}.tool + ")") (builtins.attrNames p.all))'

# Regenerate the team directory page. Output lives in kleinbem-secrets/docs/
# (private repo, plaintext — not sops-managed, same "repo privacy is the
# boundary" model as initrd/; a rendered directory page isn't meaningfully
# re-encryptable the way a discrete secret value is) because it contains
# personas' emails/names/matrix-ids.
[group("Personas")]
team:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "👥 Regenerating team page in kleinbem-secrets/docs/ (private)..."
    mkdir -p ../kleinbem-secrets/docs
    CONTACT_PATH="../kleinbem-secrets/personas/contact.nix" nix eval --raw --impure --expr \
        'let
            lib = (import <nixpkgs> {}).lib;
            contactPath = builtins.getEnv "CONTACT_PATH";
            contact = if contactPath != "" then import contactPath else {};
            p = import ./lib/personas.nix { inherit lib contact; };
         in p.teamMarkdown' \
        > ../kleinbem-secrets/docs/TEAM.md
    nix run nixpkgs#pandoc -- \
        --from=gfm --to=html5 --standalone \
        --metadata title="kleinbem.dev — Team" \
        --css="data:text/css,body{font-family:system-ui,sans-serif;max-width:900px;margin:2em auto;padding:0 1em;line-height:1.5;color:#222;background:#fafafa}h1{border-bottom:2px solid %23000;padding-bottom:0.3em}h3{margin-top:2em;color:%23005a9c}table{border-collapse:collapse;margin:1em 0}td{padding:4px 12px;border-bottom:1px solid %23ddd}td:first-child{font-weight:600;background:%23eef}hr{border:0;border-top:1px dashed %23ccc;margin:2em 0}code{background:%23eef;padding:2px 6px;border-radius:3px}" \
        ../kleinbem-secrets/docs/TEAM.md -o ../kleinbem-secrets/docs/TEAM.html
    echo "✅ Wrote $(wc -l < ../kleinbem-secrets/docs/TEAM.md) lines to kleinbem-secrets/docs/TEAM.{md,html}"

# Scaffold a persona end-to-end: signing key + sops + keys.nix patch +
# GitHub upload + mailbox. See scripts/persona-scaffold.sh for what runs.
[group("Personas")]
add name:
    @./scripts/persona-scaffold.sh {{name}}

# Apply the persona/mail DNS records only, without touching the rest of
# the Cloudflare/GitHub state. Run after editing personas.nix if it needs
# DNS changes (per-persona DKIM, Access apps). The real Terraform root is
# nix/infra — driven by nix/tools/tf-apply.sh (sops decrypt + R2 backend).
#
# SES resources (aws-ses.tf) are NOT targeted here: that file is currently
# `aws-ses.tf.disabled` (no AWS creds). Re-enable it and add its targets
# back once outbound relay is provisioned — see
# nix-config/docs/PHASE1_STALWART_STATUS.md.
[group("Personas")]
tf-apply: tf-export
    @cd ../nix && tools/tf-apply.sh -- \
        -target=cloudflare_record.mail_a \
        -target=cloudflare_record.mail_mx \
        -target=cloudflare_record.mail_spf \
        -target=cloudflare_record.mail_dmarc \
        -target=cloudflare_record.mail_mta_sts \
        -target=cloudflare_record.mail_tlsrpt \
        -target=cloudflare_record.stalwart_dkim \
        -auto-approve

# Plan persona-related Terraform without applying. Use to preview the
# infrastructure delta after editing personas.nix.
[group("Personas")]
tf-plan: tf-export
    @cd ../nix && tools/tf-apply.sh --plan-only

# Export personas.nix ⊕ contact.nix → nix/infra/personas.json so Terraform
# consumes the same source of truth. Idempotent — run before tf-apply/plan.
[group("Personas")]
[private]
tf-export:
    @../nix/tools/export-personas.sh
