# RPi kernel caching — open follow-ups

Self-contained handoff. Written so a fresh session needs no prior context.

> **Status (2026-06-23): both items appear resolved — pending one on-device
> confirmation, then drop the pin.**
>
> - **Item 1** — the *unpinned* kernel closure (`hv0qs96m…` → `kcyd0is5…` →
>   payload `xfdl6…`, plus `fkw5mx…` image and `pk9d4…` shrunk) is **fully
>   present + signed in Attic**.
> - **Item 2** — the NetBird mesh, the server-side `wt0`→caddy DNAT, *and* the
>   client-side DNS are all **working**. There is **no AAAA bug**: an earlier
>   diagnosis used `getent hosts` (legacy path); the path that matters,
>   `getent ahosts` (= `getaddrinfo`, used by nix/curl), returns **only** the
>   NetBird IPv4 on hass-pi. A 106 MiB NAR was pulled over NetBird on hass-pi
>   end-to-end.
> - **Remaining:** run the **Done when** dry-run on hass-pi to confirm the
>   unpinned kernel paths show "will be fetched", then remove the pin (the
>   removal is already staged in the working tree).

## Background (shared by both items)

**hass-pi** is a Raspberry Pi 5 NixOS host (`hosts/hass-pi/`) running Home
Assistant. It uses `pkgs.linuxPackages_rpi4` — the **`linux-rpi` vendor
kernel**, which is **not on cache.nixos.org**, so it must come from the
self-hosted **Attic** binary cache at `cache.kleinbem.dev/system` (the Attic
server runs in a container on **nixos-nvme**).

**Goal:** every hass-pi deploy should **substitute from cache, never compile
on-device**, so the **temporary kernel pin** can be removed. The pin is:

- a `nixpkgs-rpi-kernel` input in `flake.nix` (locked to nixpkgs rev
  `331800de5053fcebacf6813adb5db9c9dca22a0c`), and
- a `boot.kernelPackages = lib.mkForce (import inputs.nixpkgs-rpi-kernel …)`
  override in `hosts/hass-pi/default.nix`.

It pins the kernel to an older nixpkgs whose `linux-rpi` build is already in
hass-pi's local store (hash `r9ndv…`), keeping deploys build-free at the cost of
a frozen kernel.

**CI** (`.github/workflows/build-all.yaml`) builds host toplevels on a native
`ubuntu-24.04-arm` runner and pushes to Attic. It was fixed and is **green** as
of commit `29dcdf23`. Key CI fixes already landed this cycle:

- `nix-fast-build`'s `--flake` is **single-valued** (last wins) — the workflow
  now invokes it **once per target** in a loop (previously it silently built
  only the last `--flake`, so host toplevels were never cached).
- Build scope narrowed to **deployed host toplevels (native arch) + devShells
  (x86 only) + non-VM checks** — dropped `.#packages` (it exposed a cross-arch
  `router-1-image` that got emulated on the Intel runner).
- `sops.validateSopsFiles = false` on hass-pi so its toplevel builds in CI
  against the dummy `{}` secrets (otherwise `sops-install-secrets`'
  build-time manifest check aborts with "key 'attic_pull_token' cannot be
  found").
- `--retries 2` for transient Attic/NetBird push failures.

**Confirmed:** the kernel image (`fkw5mx…`) **and** most module paths
(`xfdl6…-modules`, `pk9d4…-modules-shrunk`, `kcyd0is5…`) **are in Attic** and
fetchable by hass-pi.

---

## Item 1 — RESOLVED: the *unpinned* modules closure is now in Attic

**Original symptom.** With the pin removed, a hass-pi toplevel dry-run listed
`hv0qs96m…-linux-rpi-6.12.75-1+rpt1-modules.drv` as **"will be built"**, while
the kernel image and other module paths fetched fine — implying a cache gap on
the modules output. The doc's `hv0qs96m`/`kcyd0is5…` hashes were **correct** —
they are what the *unpinned* config produces.

**Resolution (verified 2026-06-23).** The full **unpinned** kernel closure is
present and signed in Attic (`cache.kleinbem.dev/system`, `system:` key). The
"will be built" symptom is explained by Item 2 (the 113 MiB payload couldn't
transit Cloudflare while the mesh was down), not by a cache gap.

1. **The modules drv is single-output** — refutes the "multi-output, toplevel
   needs the non-cached output" hypothesis:

   ```
   hv0qs96mr82jl3hvih7y8b930yv69qb8-linux-rpi-6.12.75-1+rpt1-modules.drv
     → out: kcyd0is5mlg7jdw8brh6wvv4azq1bv1y-linux-rpi-6.12.75-1+rpt1-modules
   ```

2. **The whole unpinned kernel closure is in Attic** (HTTP 200, signed):

   | Path (unpinned) | Role | In Attic | NarSize |
   |---|---|---|---|
   | `kcyd0is5…-modules` | drv `out` (thin wrapper) | ✅ 200 | 360 B |
   | `xfdl6l0b…-modules` | its sole reference (payload) | ✅ 200 | **118,626,016 B (~113 MiB)** |
   | `fkw5mx21…` | kernel image | ✅ 200 | 41,370,352 B (~39 MiB) |
   | `pk9d4mm2…-modules-shrunk` | modules-shrunk | ✅ 200 | 1,891,656 B |

   `xfdl6l0b…` has **no further references** → the modules closure is complete.

> ⚠️ **Methodology trap (cost me a wrong conclusion once):** you must remove the
> pin *before* evaluating, or you measure the wrong kernel. With the pin in
> place the eval yields the **pinned** modules (`4ljajpdy…` → `i55i20rg…` →
> `bs3y9nig…`) — trivially cached and irrelevant. Only the unpinned eval yields
> the `hv0qs96m…`/`kcyd0is5…`/`xfdl6…` paths that actually matter.
>
> ⚠️ **Second trap:** a `nix-store --realise --dry-run` from the *workstation*
> (x86, multi-user daemon) is **unreliable** for this — the daemon doesn't honor
> a client-side `--option netrc-file`, so it can't authenticate to Attic and
> reports the whole closure as "will be built" (even stock `cache.nixos.org`
> paths). Verify with direct `curl`/`nix path-info --store` narinfo checks, or
> run the dry-run **on hass-pi** (where Attic is configured). See **Done when**.

**Why it wasn't "done" → Item 2.** The payload `xfdl6l0b…` is **113 MiB, over
Cloudflare's 100 MiB per-NAR cap**. It is in Attic but hass-pi can only pull it
over the NetBird mesh — which is now working (see Item 2). End-to-end transport
of a 106 MiB NAR over NetBird was confirmed on hass-pi
(`http=200 via=100.117.212.232 size=111638005 time=3.6s`).

---

## Item 2 — RESOLVED: NetBird transport works end-to-end (no AAAA bug)

> **All of Item 2 is resolved (verified 2026-06-23).** The mesh is up, the
> server-side `wt0`→caddy DNAT is live, and hass-pi resolves
> `cache.kleinbem.dev` to the NetBird IPv4 for real applications. The earlier
> "AAAA shadows the override" diagnosis was **wrong** — it came from using
> `getent hosts` instead of `getent ahosts`. A 106 MiB NAR was pulled over
> NetBird on hass-pi, proving the Cloudflare 100 MiB cap is bypassed.

**Original symptom.** hass-pi could fetch *small* paths from Attic but not *big*
NARs (the modules payload is 113 MiB), apparently reaching Attic via
**Cloudflare**, whose **100 MiB per-NAR cap** chokes big closures (the 39 MiB
kernel image squeaks through; the 113 MiB modules NAR did not). The design
routes big NARs over the **NetBird WireGuard mesh** — CI does this via an
`/etc/hosts` override on its IPv4-only runner (`.github/actions/nix-fleet-setup`).

**RESOLVED — NetBird mesh + server transport (verified 2026-06-23 on nixos-nvme).**
The old "Peers count: 0/42, peer-to-peer not establishing" reading was **stale
and misdiagnosed**:

- `netbird status -d` on nixos-nvme: **Management Connected** (`api.netbird.io`),
  **Signal Connected** (`signal.netbird.io`), **all Relays Available**
  (STUN/TURN/`rels`). Count is now `1/63` — but **~60 of the 63 "peers" are dead
  ephemeral CI runner VMs** (`runnervm*`) permanently stuck "Connecting" because
  the VMs no longer exist. They inflate the denominator; they are not a failure.
- **hass-pi (`100.117.163.227`) is `Connected`, `Connection type: P2P`** —
  direct over the shared LAN (remote endpoint `10.0.0.21:51820`), last WireGuard
  handshake ~1 min ago, **latency 3.2 ms**; `ping` over `wt0` = 0% loss,
  ~1.7 ms.
- **Server-side cache transport is live**: `hosts/nixos-nvme/network.nix`
  DNATs `iifname "wt0" tcp dport { 80, 443 }` → the caddy container
  (`10.85.46.107`) with a matching `wt0` accept; the live ruleset shows the rule
  in place and **~5.0 GB already received over `wt0`**.
- ⚠️ **Testing artifact to avoid:** `curl --resolve cache.kleinbem.dev:443:100.117.212.232`
  *from nixos-nvme itself* returns `000`. That is a **false negative** — the
  DNAT only matches traffic *ingressing* on `wt0`, and locally-originated
  packets to the local `wt0` IP never traverse `wt0`. (The doc's original
  "curl → 000" symptom was almost certainly this same artifact, wrongly read as
  "0 peers connected.") The valid test must run **on hass-pi**.

**There is no AAAA bug — the override works (verified on hass-pi).** The
`networking.hosts."100.117.212.232" = [ "cache.kleinbem.dev" ]` entry from
`modules/nixos/attic-pull.nix` is present in hass-pi's `/etc/hosts`, and the
resolution path that nix/curl actually use honors it:

| Command | Returns | Used by |
|---|---|---|
| `getent hosts cache.kleinbem.dev` | Cloudflare IPv6 AAAA | nothing real (legacy path) |
| `getent ahosts cache.kleinbem.dev` | **only `100.117.212.232`** | **`getaddrinfo()` → nix, curl** |

nsswitch is `… files … dns` (files first) and `systemd-resolved` is inactive, so
`/etc/hosts` is authoritative for `getaddrinfo`. The earlier "glibc prefers
AAAA" reading was an artifact of querying with `getent hosts` (a different,
legacy resolver path) instead of `getent ahosts`. **No code change is needed.**

**Transport proven end-to-end (on hass-pi).** Pulling the 113 MiB modules
payload's NAR over the NetBird-resolved name:

```
http=200 via=100.117.212.232 size=111638005 time=3.646632s
```

106 MiB downloaded via the NetBird IP in 3.6 s with no 413 — a transfer that
size would have been killed by Cloudflare's 100 MiB cap, so this confirms the
mesh path is in use and the cap is bypassed.

Then validate **on hass-pi** with the `Done when` dry-run below.

---

## Done when

Both items verified → confirm **on hass-pi** that the unpinned kernel closure
substitutes (uses hass-pi's real Attic + netrc + NetBird routing; needs no
flake checkout — just the known store paths):

```bash
nix-store -r --dry-run --option narinfo-cache-negative-ttl 0 \
  /nix/store/fkw5mx21wkkhd5naqcwilbnjdn22r5qp-linux-rpi-6.12.75-1+rpt1 \
  /nix/store/kcyd0is5mlg7jdw8brh6wvv4azq1bv1y-linux-rpi-6.12.75-1+rpt1-modules \
  /nix/store/pk9d4mm2df2wigbz7hd1dh0iqm82zkmy-linux-rpi-6.12.75-1+rpt1-modules-shrunk
```

All three show **"will be fetched"** → remove the pin (the `nixpkgs-rpi-kernel`
input in `flake.nix` + the `boot.kernelPackages` override in
`hosts/hass-pi/default.nix`, then `nix flake lock`) → hass-pi tracks the current
kernel, fully build-free. (The pin removal is currently staged in the working
tree, pending this confirmation.)
