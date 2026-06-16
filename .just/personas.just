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

[group("Personas")]
list:
    @echo "🎭 Personas declared in personas.nix:"
    @nix eval --raw --file personas.nix --apply \
        'p: builtins.concatStringsSep "\n" (map (n: "  - " + p.${n}."full-name" + " <" + p.${n}.email + ">  (" + p.${n}.tool + ")") (builtins.attrNames p))'

# Regenerate the team directory page. Output lives in
# nix-secrets/docs/ (private repo) because it contains personas'
# emails / names / matrix-ids — same reason personas-contact.nix
# is in nix-secrets, not nix-config.
[group("Personas")]
team:
    @echo "👥 Regenerating team page in nix-secrets/docs/ (private)..."
    @mkdir -p ../nix-secrets/docs
    @nix eval --raw --impure --expr \
        'let \
            lib = (import <nixpkgs> {}).lib; \
            contactPath = ../nix-secrets/personas-contact.nix; \
            contact = if builtins.pathExists contactPath then import contactPath else {}; \
            p = import ./lib/personas.nix { inherit lib contact; }; \
         in p.teamMarkdown' \
        > ../nix-secrets/docs/TEAM.md
    @nix run nixpkgs#pandoc -- \
        --from=gfm --to=html5 --standalone \
        --metadata title="kleinbem.dev — Team" \
        --css="data:text/css,body{font-family:system-ui,sans-serif;max-width:900px;margin:2em auto;padding:0 1em;line-height:1.5;color:#222;background:#fafafa}h1{border-bottom:2px solid %23000;padding-bottom:0.3em}h3{margin-top:2em;color:%23005a9c}table{border-collapse:collapse;margin:1em 0}td{padding:4px 12px;border-bottom:1px solid %23ddd}td:first-child{font-weight:600;background:%23eef}hr{border:0;border-top:1px dashed %23ccc;margin:2em 0}code{background:%23eef;padding:2px 6px;border-radius:3px}" \
        ../nix-secrets/docs/TEAM.md -o ../nix-secrets/docs/TEAM.html
    @echo "✅ Wrote $(wc -l < ../nix-secrets/docs/TEAM.md) lines to nix-secrets/docs/TEAM.{md,html}"

# Scaffold a persona end-to-end: signing key + sops + keys.nix patch +
# GitHub upload + mailbox. See scripts/persona-scaffold.sh for what runs.
[group("Personas")]
add name:
    @./scripts/persona-scaffold.sh {{name}}

# Apply persona-related Terraform resources only (DNS, SES, etc.) without
# touching the rest of the Cloudflare/GitHub state. Run after editing
# personas.nix if it requires DNS changes (per-persona DKIM, Access apps).
[group("Personas")]
tf-apply: tf-export
    @cd ../terraform && tofu apply \
        -target=cloudflare_record.mail_a \
        -target=cloudflare_record.mail_mx \
        -target=cloudflare_record.mail_spf \
        -target=cloudflare_record.mail_dmarc \
        -target=cloudflare_record.mail_mta_sts \
        -target=cloudflare_record.mail_tlsrpt \
        -target=aws_sesv2_email_identity.primary_domain \
        -target=aws_iam_user.stalwart_smtp \
        -target=aws_iam_access_key.stalwart_smtp

# Plan persona-related Terraform without applying. Use to preview the
# infrastructure delta after editing personas.nix.
[group("Personas")]
tf-plan: tf-export
    @cd ../terraform && tofu plan

# Export personas.nix → terraform/personas.json so Terraform can consume
# the same source of truth. Idempotent — run before any tf-apply/plan.
[group("Personas")]
[private]
tf-export:
    @../scripts/export-personas.sh
