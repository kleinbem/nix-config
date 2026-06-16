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

# Regenerate docs/TEAM.md from personas.nix + personas-state.nix.
# Idempotent — safe to run at any time. Writes a markdown directory
# page rendering every persona's identity + current lifecycle state.
[group("Personas")]
team:
    @echo "👥 Regenerating team page..."
    @nix eval --raw --impure --expr \
        'let p = import ./lib/personas.nix { lib = (import <nixpkgs> {}).lib; }; in p.teamMarkdown' \
        > docs/TEAM.md
    @echo "✅ Wrote $(wc -l < docs/TEAM.md) lines to nix-config/docs/TEAM.md"

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
