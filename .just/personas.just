import 'common.just'

set working-directory := ".."

# --- Persona orchestration ---
# Add a persona: edit personas.nix, run `just personas::add <name>`, then
# `just personas::tf-apply` only if DNS records need to change.

# Both recipes below import kleinbem-secrets/personas/contact.nix, plain Nix
# protected by the private repo: names and emails go public with a persona's
# first commit anyway.
#
# List declared personas
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

# Output goes to kleinbem-secrets (private, plaintext): it lists personas'
# names and emails.
#
# Regenerate the team directory page in kleinbem-secrets/docs/
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

# SES isn't targeted while nix/infra/aws-ses.tf.disabled has no AWS creds;
# see docs/PHASE1_STALWART_STATUS.md.
#
# Apply only the mail DNS records in nix/infra (via nix/tools/tf-apply.sh)
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

# Regenerate nix/infra/{personas,inventory}.json from personas.nix ⊕
# contact.nix + inventory.nix so OpenTofu consumes the same source of truth.
# Idempotent — run before tf-apply/plan.
[group("Personas")]
[private]
tf-export:
    @../nix/tools/gen-iac-data.sh
