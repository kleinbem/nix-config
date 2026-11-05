# Stalwart mail

Persona mail server. Runs as the `stalwart` container on **mac-mini**, internal only.

## How it works

| Thing | Value | Where |
|---|---|---|
| Container | `stalwart` on mac-mini, `10.85.50.8` on cbr0 | `hosts/mac-mini/default.nix`, `inventory.nix` `network.nodes.stalwart` |
| Module | Stalwart 0.15, `services.stalwart` inside the container | `nix-presets/containers/stalwart.nix` |
| Build | Standalone image from container-factory, pulled by the host's container updater | `hosts/container-factory/default.nix` |
| Data | host `/var/lib/stalwart` (RocksDB), backed up as a `secure` item of `my.backup` | preset |
| Domain | `kleinbem.dev`, hostname `mail.kleinbem.dev` | preset |
| Listeners | smtp 25, submission 587, imap 143, http 8080 (JMAP + webadmin, no TLS) | preset |
| Fallback admin | user `admin`; sops holds only the sha-512 hash, the plaintext is in Bitwarden | `stalwart_admin_password_hash` in `kleinbem-secrets/nix/per-container/stalwart.yaml` |
| Automation account | principal `automation`, used by `persona-scaffold.sh` | `stalwart_automation_password` in the same file |
| Mailboxes | one `<first>.<last>@kleinbem.dev` per persona, created through the API, not declared in Nix | `scripts/persona-scaffold.sh` |
| Outbound relay | none: direct delivery, fine for persona-to-persona mail | preset `relaySecretFile` |

The admin secret is per-container (not per-host) so the mail server can move hosts.

`automation` has the `admin` role because it creates principals. A custom Stalwart role with only the principal permissions would be narrower; that isn't set up.

## Add a mailbox

```bash
just personas::add <persona>
```

`persona-scaffold.sh` generates the persona's mailbox password into `kleinbem-secrets/personas/<persona>.yaml` if missing, then `POST`s the principal from mac-mini to `http://10.85.50.8:8080/api/principal` as `automation`. It doesn't use `stalwart-cli`: that needs `/api/schema`, which 0.15 doesn't have. HTTP 400 usually means the mailbox already exists.

## Rotate a password

**Fallback admin:** new password into Bitwarden, then put its `mkpasswd -m sha-512` hash into `stalwart_admin_password_hash` (`sops kleinbem-secrets/nix/per-container/stalwart.yaml`), merge, and let mac-mini deploy. Add a line to `kleinbem-secrets/ROTATIONS.md`.

**Automation or a mailbox:** the create call only works once, so update the existing principal's secret on the server and in sops together:

```bash
NEW_PW=$(openssl rand -base64 32)
jq -n --arg pw "$NEW_PW" '[{action:"set", field:"secrets", value:[$pw]}]' \
  | ssh mac-mini 'curl -sS -u admin:<BITWARDEN_PLAINTEXT> -H "Content-Type: application/json" \
      -X PATCH http://10.85.50.8:8080/api/principal/<name> --data-binary @-'
```

Then store `NEW_PW` under the matching key: `stalwart_automation_password` in `nix/per-container/stalwart.yaml`, or `mailbox_password` in `personas/<persona>.yaml`.

## Verify

```bash
ssh mac-mini 'machinectl status stalwart; journalctl -u container@stalwart -n 30'

# list mailboxes (run on mac-mini; the container ships no curl)
ssh mac-mini "curl -sS -u automation:\$PW 'http://10.85.50.8:8080/api/principal?types=individual'"
```

`PW` is `sops -d --extract '["stalwart_automation_password"]' kleinbem-secrets/nix/per-container/stalwart.yaml`. A commit as a persona checks the identity end to end: `just as <persona> save-all "chore: mail smoke test"` from `nix/`.

## Bitwarden entry

| Field | Value |
|---|---|
| Name | `Stalwart Mail — admin` |
| Username | `admin` |
| URI | `http://10.85.50.8:8080` (webadmin) |
| Notes | Hash in `kleinbem-secrets/nix/per-container/stalwart.yaml` as `stalwart_admin_password_hash` |

## External mail

Nothing outside the mesh can deliver to `@kleinbem.dev`: web ingress is a Cloudflare Tunnel, which can't carry SMTP, and `var.mail_host_ip` in `nix/infra` stays empty (the A record is count-gated). Options: a small VPS as MX smarthost over NetBird, or an inbound relay service.

Outbound to the internet needs a relay. `nix/infra/aws-ses.tf.disabled` is the SES draft; any SMTP provider works. Set `relaySecretFile` (a file with `USERNAME=` / `PASSWORD=` lines) on the mac-mini container block and on the container-factory entry (a dummy there).

`inventory.nix` `git.email` stays on gmail until a `@kleinbem.dev` mailbox is verified on the GitHub account, or signed pushes to protected branches break.
