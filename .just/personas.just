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

# Both recipes below decrypt kleinbem-secrets/personas/contact.nix (real PII
# — names/emails/Matrix IDs, whole-file sops binary-mode) into a tmpfs temp
# file, `import` THAT instead of the ciphertext, then shred it on exit.
# Interactive recipes (unlike hosts/mac-mini/secrets.nix's old approach) can
# just shell out to sops directly — no Nix-eval-time constraint here. Fixed
# 2026-08-08; previously read plaintext from the legacy nix-secrets repo.
[group("Personas")]
list:
    #!/usr/bin/env bash
    set -euo pipefail
    WORK="$(mktemp -d /dev/shm/personas-list-XXXXXX)"
    trap 'find "$WORK" -type f -exec shred -u {} \; 2>/dev/null; rm -rf "$WORK"' EXIT
    sops -d --input-type binary --output-type binary ../kleinbem-secrets/personas/contact.nix > "$WORK/contact.nix"
    echo "🎭 Personas declared in personas.nix:"
    CONTACT_PATH="$WORK/contact.nix" nix eval --raw --impure --expr \
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
    WORK="$(mktemp -d /dev/shm/personas-team-XXXXXX)"
    trap 'find "$WORK" -type f -exec shred -u {} \; 2>/dev/null; rm -rf "$WORK"' EXIT
    sops -d --input-type binary --output-type binary ../kleinbem-secrets/personas/contact.nix > "$WORK/contact.nix"
    echo "👥 Regenerating team page in kleinbem-secrets/docs/ (private)..."
    mkdir -p ../kleinbem-secrets/docs
    CONTACT_PATH="$WORK/contact.nix" nix eval --raw --impure --expr \
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
