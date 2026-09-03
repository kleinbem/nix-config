# Phase 1 — Stalwart Mail: status & runbook

Companion to `PHASE1_STALWART.md` (the original scaffold). This tracks the
current wired state and what's left.

## TL;DR

- **Wired, `enable = true`, committed.** The Stalwart container is defined
  on **mac-mini** (24/7 host). Once CI builds + promotes its closure and
  mac-mini switches, it comes up.
- **Personas have email identities** (`<first>.<last>@kleinbem.dev`, all 6,
  in `kleinbem-secrets/personas/contact.nix` — already used for git commit
  authorship). Working **mailboxes** exist only after the deploy + the
  `persona-scaffold.sh` loop below.

## What's wired

| Thing | Value | Where |
|---|---|---|
| Host | **mac-mini** — always-on; nixos-nvme was rejected (workstation, not 24/7) | `hosts/mac-mini/default.nix` |
| Container IP | `10.85.50.8/24` (mac-mini's `.50` container subnet) | `inventory.nix` `network.nodes.stalwart` |
| Data dir | host `/var/lib/stalwart` → container `/var/lib/stalwart`; RocksDB `db` store at `/var/lib/stalwart/db` | preset + `default.nix` |
| Mail domain | `kleinbem.dev`; `server.hostname = mail.kleinbem.dev` (preset) | preset |
| Listeners | smtp 25, submission 587, imap 143, http 8080 (JMAP + webadmin) | preset |
| Admin | fallback-admin `admin`; secret `stalwart_admin_password_hash` via systemd `LoadCredential` → `%{file:…}%` macro | preset + `mac-mini/secrets.nix` |
| Admin secret scope | **per-container**: `kleinbem-secrets/nix/per-container/stalwart.yaml` (not per-host — the mail server is a fleet service that can migrate; `.sops.yaml` catch-all already encrypts it to martin + nixos_nvme + mac_mini) | `mac-mini/secrets.nix` |
| Mailboxes | one `<first>.<last>@kleinbem.dev` per persona, created **imperatively** by `scripts/persona-scaffold.sh` (`stalwart-cli`), not declared in Nix | `scripts/persona-scaffold.sh` |
| Outbound relay | none (`relaySecretFile` unset) → Stalwart direct delivery; fine for mesh-internal persona↔persona mail | preset |
| Standalone build | catalogue + import in `hosts/container-factory/default.nix`; mac-mini is a `deploySources` host so `deployedContainers` picks it up | `container-factory/default.nix` |

### Preset rewrite (`nix-presets/containers/stalwart.nix`)

The old preset couldn't be enabled: it `import`ed `nix-config/personas.nix`
(forbidden cross-repo dep; the path also doesn't resolve store-fetched) and
read `p.email`/`p.full-name` which aren't in the public manifest; it used
`services.stalwart-mail` (renamed to `services.stalwart` upstream) and
`queue.*.next-hop` (now a build-time assertion failure — v0.13 replaced it
with `queue.strategy.route`); `directory.internal type = "memory"` is
read-only so `stalwart-cli` can't create accounts; and `stateVersion`
(required, no default) was unset.

Rewritten to the **Stalwart 0.15** schema: `services.stalwart`, explicit
`stateVersion = "26.05"`, four listeners, fallback-admin via
`LoadCredential`, storage/directory left to the module's RocksDB defaults,
outbound relay in the v0.13+ `queue.strategy.route` shape gated behind
`relaySecretFile`. Verified by building the container toplevel through
`container-factory`: real `stalwart.toml`, no failed assertions.

Also fixed: `.just/personas.just` `tf-apply`/`tf-plan`/`tf-export` pointed
at a non-existent `../terraform` + `../scripts/export-personas.sh`; now
delegate to `nix/tools/*` against `nix/infra`, SES targets dropped.

## Deploy — your steps

sops is **done** (`stalwart_admin_password_hash` is in
`kleinbem-secrets/nix/per-container/stalwart.yaml`).

```bash
# 1. wait for CI on the enable commit, on mac-mini's arch (x86_64):
#      Build & Cache All (Fast)  → builds stalwart's closure → Attic
#      Promote → production      → publishes it into the manifest
cd ~/Develop/github.com/kleinbem/nix && just jj::remote-ci   # or GitHub Actions

# 2. deploy mac-mini (YubiKey). It's headless — deploy remotely:
cd ~/Develop/github.com/kleinbem/nix-config
just in nix-config nixos::switch            # if run ON mac-mini
#   otherwise your usual remote path for mac-mini (colmena / deploy script)
#   container-updater-bootstrap then stages stalwart from the manifest.
#   If you switch before Promote finished:
#      ssh mac-mini 'sudo systemctl start update-container@stalwart'

# 3. check it's up
ssh mac-mini 'machinectl status stalwart; journalctl -u container@stalwart -n 30'

# 4. mailboxes — one per persona (idempotent)
#    First confirm the 0.15 stalwart-cli auth flags:
ssh mac-mini 'machinectl shell stalwart /run/current-system/sw/bin/stalwart-cli --help'
#      likely: -u https://localhost:8080 -c admin:<password>
for p in martin michael-gruber thomas-schmidt daniel-meier rahul-kumar juan-gonzalez; do
  just personas::add "$p"
done
ssh mac-mini 'machinectl shell stalwart /run/current-system/sw/bin/stalwart-cli account list'

# 5. smoke test
just jj::as michael-gruber save-all "chore: mail smoke test"
```

Runtime unknowns (discoverable once up, none block the build): `stalwart-cli`
0.15 auth flags (step 4); the `queue.route` relay shape (only when a relay
is added — TODO in the preset); a real TLS cert (self-signed STARTTLS is
fine on the trusted `cbr0` bridge).

## Bitwarden entry (the fallback-admin password)

sops holds only the **hash**; the plaintext (webadmin login + `stalwart-cli`)
isn't recoverable from it — keep it in Bitwarden.

| Field | Value |
|---|---|
| Type | Login |
| Name | `Stalwart Mail — admin` |
| Username | `admin` |
| Password | the plaintext you generated (its `mkpasswd -m sha-512` hash is the sops value) |
| URI | `https://10.85.50.8:8080` (webadmin; self-signed cert). Add `https://mail.kleinbem.dev:8080` later. |
| Notes | Fallback admin for the Stalwart mail container on **mac-mini** (persona fleet, Phase 1). Hash lives in `kleinbem-secrets/nix/per-container/stalwart.yaml` as `stalwart_admin_password_hash`. Rotate: new password → `mkpasswd -m sha-512` → update that sops key → redeploy mac-mini. |

Custom fields (text):

| Name | Value |
|---|---|
| sops-key | `stalwart_admin_password_hash` in `kleinbem-secrets/nix/per-container/stalwart.yaml` |
| host | mac-mini · container `stalwart` · 10.85.50.8 |
| cli | `machinectl shell stalwart /run/current-system/sw/bin/stalwart-cli -u https://localhost:8080 -c admin:<password>` (verify flags) |
| hash-cmd | `mkpasswd -m sha-512` |

Also add a line to `kleinbem-secrets/ROTATIONS.md`.

## Later, only if personas need EXTERNAL mail

### Inbound reachability — architectural

The fleet is all-`10.x`; web ingress is Cloudflare Tunnel, which can't
carry SMTP. Nothing external can deliver to `@kleinbem.dev` today. Options:
(A) internal-only, nothing to do; (B) cheap VPS as MX smarthost over
NetBird; (C) an inbound relay service. Until B/C, leave
`var.mail_host_ip = ""` (default; the A record is count-gated).

### Outbound relay

`nix/infra/aws-ses.tf.disabled` — needs an AWS account, or swap in
Brevo/Mailgun/etc. (`relaySecretFile` takes any `USERNAME=`/`PASSWORD=`
SMTP pair). Set `relaySecretFile` on **both** the mac-mini container block
and the `container-factory` catalogue entry (dummy on the factory).

## Follow-ups gated on Phase 1 completion

- `inventory.nix` `git.email` stays `…@gmail.com` until a real
  `@kleinbem.dev` mailbox exists AND is verified on the GitHub account
  (switching early breaks signed pushes to branch-protected repos).
- aider / thomas-schmidt in `[[project_ai_second_brain_plan]]` is unblocked
  once the persona mailboxes exist (step 4).
