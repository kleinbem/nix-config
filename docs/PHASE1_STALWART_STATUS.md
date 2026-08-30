# Phase 1 — Stalwart Mail: status & decisions (2026-08-30)

Companion to `PHASE1_STALWART.md` (the original scaffold). That doc lists 7
manual steps; this one records **where we actually are**, which decisions
are now made, and the three things that still need a human call.

## TL;DR

- **Is the mailserver set up?** Config is fully wired and eval-validated
  (the container OS closure builds), but **`enable = false` — nothing is
  deployed**. No `stalwart` container is running on any host.
- **Do the personas have email addresses?** As **identities**, yes — all 6
  (`martin` + 5 agents) have `<first>.<last>@kleinbem.dev` in
  `kleinbem-secrets/personas/contact.nix`, already used as git commit
  authorship. As **working mailboxes** you can send/receive on, no.

## Validation done (this change)

- `nixos-nvme` full toplevel evaluates to a `.drv` with the new container
  block at `enable = false` — the gated secret is absent, zero activation
  footprint (verified against both the currently-pinned and the local
  preset).
- `container-factory` (the ADR-002 standalone build host) with `stalwart`
  in `preWarm`: the container's `services.stalwart` closure builds — real
  `stalwart.toml` generated, **no failed assertions**, `stateVersion` +
  `directory.internal` (persistent RocksDB `db` store) + 4 listeners +
  `authentication.fallback-admin` + systemd `LoadCredential` all correct.
  `nix build …container-factory…containers.stalwart.config.system.build.toplevel`
  → `/nix/store/…-nixos-system-stalwart-26.11…` built clean.
- `pkgs.stalwart` is **0.15.5** on the pinned nixpkgs.

## What is now decided & wired (this change)

| Decision | Value | Where |
|---|---|---|
| Host | **nixos-nvme** — already runs the whole container fleet + `container-updater` auto-derivation; Stalwart is ~200 MB–1 G RAM | `hosts/nixos-nvme/containers.nix` |
| Container IP | **10.85.46.140** on `cbr0` | `inventory.nix` (`network.nodes.stalwart`), `containers.nix` |
| Data dir | `/var/lib/images/stalwart` (+ tmpfiles rule); RocksDB at `/var/lib/stalwart/db` inside | `containers.nix` |
| Mail domain / MX target | `kleinbem.dev` / `mail.kleinbem.dev` (preset sets `server.hostname` automatically) | preset default |
| Mailbox set | one `<first>.<last>@kleinbem.dev` per persona, created imperatively by `persona-scaffold.sh` (see "Preset bug fixed" below) | `scripts/persona-scaffold.sh` |
| Admin | fallback-admin `admin` / secret from `stalwart_admin_password_hash`, via systemd `LoadCredential` → `%{file:…}%` macro. Secret **gated behind `my.containers.stalwart.enable`** (same footgun-avoidance as `litellm_master_key`) | `secrets.nix` + preset |
| Outbound relay | **none for now** (`relaySecretFile` unset) → Stalwart's built-in direct delivery; fine for mesh-internal persona↔persona mail | `containers.nix` |
| Standalone build | added to `hosts/container-factory/default.nix` (import + catalogue, dummy `adminPasswordFile`); once nixos-nvme's `enable = true`, `deployedContainers` picks it up automatically | `container-factory/default.nix` |
| `enable` | **`false`** — flips on once the admin hash is provisioned | `containers.nix` |

### Preset bug fixed (`nix-presets/containers/stalwart.nix`)

The preset used to `import ../../nix-config/personas.nix` and build a
static `directory.internal` principal list from `p.email` / `p.full-name`.
Both wrong: nix-presets must not import nix-config (its own CLAUDE.md
"Don't"; the path also doesn't resolve when nix-presets is a store-fetched
input), and `email`/`full-name` aren't in the public manifest — they're in
`kleinbem-secrets/personas/contact.nix`. Enabling the container would have
failed eval on the missing attrs.

**Decision — mailbox provisioning is imperative, not declarative.** The
persona import + principal list are gone. Accounts are created by
`scripts/persona-scaffold.sh` step 6 (`stalwart-cli account create
<email> <full-name>`), which already resolves identity from the joined
`lib/personas.nix` view at script runtime — no `contact.nix` in NixOS
module eval (keeps the "no module imports contact data" rule intact).

The whole preset was rewritten to the **Stalwart 0.15 `services.stalwart`
schema** (option renamed from `services.stalwart-mail` in nixpkgs; the old
preset's `queue.*.next-hop` is now a build-time assertion failure, so
outbound relay moved to the v0.13+ `queue.strategy.route` shape, gated
behind `relaySecretFile`). Storage/directory/store are left to the NixOS
module defaults (RocksDB `db` store, `directory.internal.type =
"internal"`) — verified correct by building the closure. `stateVersion =
"26.05"` is set explicitly (the module requires it, no default).

Also fixed in passing: `.just/personas.just` `tf-apply` / `tf-plan` /
`tf-export` pointed at a non-existent `../terraform` and
`../scripts/export-personas.sh`. They now delegate to the real
`nix/tools/tf-apply.sh` + `nix/tools/export-personas.sh` against
`nix/infra`, and no longer target the disabled SES resources.

## The three calls that still need a human

### 1. Inbound mail reachability — **architectural, unsolved**

The fleet is entirely on `10.x`; web ingress is via Cloudflare Tunnel,
which **cannot carry SMTP** (port 25). So today nothing external can
deliver to `@kleinbem.dev`. Options:

| Option | Effort | Notes |
|---|---|---|
| **A. Internal-only mail (recommended now)** | zero | Personas email each other + `martin` over the mesh. No inbound MX needed. Enough for agent coordination / CI notifications consumed internally. |
| B. Cheap VPS as MX smarthost | ~half a day | VPS holds the public IP, runs as inbound relay, forwards over NetBird to Stalwart. Also solves outbound reputation (see #2). |
| C. Inbound relay service (mxroute/purelymail/…) | ~1 h + $ | They hold the MX; Stalwart pulls or receives forwarded mail. |

Until B or C, leave the `mail.kleinbem.dev` A record unset
(`var.mail_host_ip = ""` — already the default, record is count-gated) and
don't rely on external delivery.

### 2. Outbound relay — **blocked on AWS creds (or pick another provider)**

`nix/infra/aws-ses.tf.disabled` is disabled "until AWS creds exist".
Direct send from a residential IP will be spam-filtered. Decide:
enable SES (needs an AWS account + IAM user + SMTP creds → sops
`stalwart/ses-smtp-credentials`), or swap in a transactional provider
(Brevo / MailerSend / Mailgun) — `relaySecretFile` takes any
`username=/password=` SMTP pair, so the Nix side doesn't care.

Not urgent: personas don't send outward yet.

### 3. Deploy + mailbox init — **needs YubiKey + a running container**

```bash
# 0. land the preset — nix-config's flake.lock still pins the OLD nix-presets
#    (buggy stalwart preset; harmless only while enable = false).
cd ~/Develop/github.com/kleinbem/nix-presets
just jj::save-all "feat(stalwart): 0.15 schema, imperative mailboxes, fix persona import" nix-presets
just jj::push-all nix-presets
cd ~/Develop/github.com/kleinbem/nix-config
nix flake update nix-presets            # pull the pushed preset

# 1. admin secret (fallback-admin password; hash or plaintext both work)
mkpasswd -m sha-512 > /tmp/h && sops --set '["stalwart_admin_password_hash"] "'"$(cat /tmp/h)"'"' \
  ~/Develop/github.com/kleinbem/nix-secrets/nix/per-host/nixos-nvme.yaml ; shred -u /tmp/h
#   (or just: sops ~/…/nix-secrets/nix/per-host/nixos-nvme.yaml  and add the key by hand)

# 2. enable + deploy
sed -i 's/    stalwart = {\n      enable = false;/    stalwart = {\n      enable = true;/' \
  hosts/nixos-nvme/containers.nix          # or edit by hand
just in nix-config nixos::switch            # touches YubiKey; builds the container closure + activates

# 3. mailboxes — one per persona (idempotent)
for p in martin michael-gruber thomas-schmidt daniel-meier rahul-kumar juan-gonzalez; do
  just personas::add "$p"
done
#   step 6 of persona-scaffold.sh runs `stalwart-cli account create`. VERIFY the
#   0.15 stalwart-cli auth flags first: `machinectl shell stalwart /run/current-system/sw/bin/stalwart-cli --help`
#   — it likely needs `-u https://localhost:8080 -c admin:<secret>` or a CREDENTIALS env.

# 4. (optional, external delivery only) DKIM
machinectl shell stalwart /run/current-system/sw/bin/bash -c \
  'stalwart-cli dkim create kleinbem.dev || journalctl -u stalwart | grep -i dkim'
#   take the base64 pubkey → TF_VAR_stalwart_dkim_pubkey_b64 → `just personas::tf-apply`

# 5. smoke test
just jj::as michael-gruber save-all "chore: mail smoke test"
machinectl shell stalwart /run/current-system/sw/bin/stalwart-cli account list
```

Remaining runtime unknowns (all discoverable once it's up, none block the build):
`stalwart-cli` 0.15 auth flags (step 3 note); the `queue.route` relay shape
(only when SES/relay is added — TODO in the preset); a real TLS cert
(self-signed STARTTLS is fine on the trusted `cbr0` bridge).

## Follow-ups gated on Phase 1 completion

- `inventory.nix` `git.email` is deliberately still `…@gmail.com` — switch
  to `martin.kleinberger@kleinbem.dev` only after that mailbox exists AND
  is verified on the GitHub account, or signed pushes to branch-protected
  repos break.
- `MEMORY.md` → "AI + second-brain plan": aider (thomas-schmidt) is blocked
  on persona signing keys / mailboxes; unblocked by step 4 above.
