# RPi kernel caching — open follow-ups

Self-contained handoff for the two remaining items blocking **build-free hass-pi
deploys**. Written so a fresh session needs no prior context.

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

## Item 1 — Toplevel rebuilds `hv0qs96m` kernel-modules despite them being cached

**Symptom.** With the pin removed, on hass-pi:

```bash
nix-store -r <hass-pi-toplevel.drv> --dry-run --option narinfo-cache-negative-ttl 0
```

lists **`hv0qs96m…-linux-rpi-6.12.75-1+rpt1-modules.drv` as "will be built"** —
yet:

- the kernel image (`fkw5mx…`) → **fetched** from Attic ✅
- other module paths (`xfdl6…-modules`, `pk9d4…-modules-shrunk`) → **fetched** ✅
- `hv0qs96m`'s output path (`kcyd0is5…-modules`) queried **directly**
  (`nix-store -r /nix/store/kcyd0is5… --dry-run`) → **"will be fetched"** ✅

So the output **exists in Attic**, but the toplevel still resolves the `.drv`
to build.

**Hypothesis.** `hv0qs96m.drv` is **multi-output** and the toplevel needs an
output that *isn't* the cached one; OR CI builds a slightly different
`hv0qs96m` (CI uses `--override-input nix-secrets /tmp/dummy-secrets` = empty
`{}`, producing a different toplevel hash — though the modules were verified
earlier to be *secret-independent*, so this is the less likely cause).

**Next steps.**

1. `nix derivation show <hv0qs96m.drv>` → list **all outputs**.
2. For each output, `nix path-info --store https://cache.kleinbem.dev/system
   <out>` (with hass-pi's pull token / netrc) → which output is cached vs which
   the toplevel references.
3. Confirm CI's `hv0qs96m` hash equals the real hass-pi config's (build the real
   toplevel locally vs the dummy-secrets one and diff the modules drv).

---

## Item 2 — NetBird mesh not connecting (0/42) + Cloudflare-IPv6 routing

**Symptom.** hass-pi can fetch *small* paths from Attic but not *big* NARs (the
modules are 113 MiB unpacked), because:

- `netbird status` on nixos-nvme shows **"Peers count: 0/42 Connected"** —
  NetBird management is up but **peer-to-peer connections aren't establishing**.
- On hass-pi, `getent hosts cache.kleinbem.dev` resolves to **Cloudflare IPv6**
  (`2606:4700:…`), so the IPv4 NetBird override
  (`networking.hosts."100.117.212.232" = ["cache.kleinbem.dev"]` in
  `modules/nixos/attic-pull.nix`) is **bypassed** (glibc prefers the AAAA
  record).
- `curl` from hass-pi to `100.117.212.232:443` (nixos-nvme's NetBird IP) →
  **`000` (can't connect)** — consistent with 0 peers connected.

**Result.** hass-pi reads Attic via **Cloudflare**, whose **100 MiB per-NAR
cap** chokes big closures (the 39.5 MiB kernel image squeaks through; a large
modules NAR would not). The intended design routes big NARs over the **NetBird
WireGuard mesh** — CI does exactly this via an `/etc/hosts` override on its
IPv4-only runner (see `.github/actions/nix-fleet-setup`).

**Next steps.**

1. Diagnose **why NetBird peers won't connect** (`netbird status -d`): relays /
   STUN reachability, firewall, NAT type. nixos-nvme is `100.117.212.232`,
   hass-pi enrolled as `100.117.163.227`.
2. Once peers connect, force `cache.kleinbem.dev` to route over **NetBird
   IPv4 / `wt0`** instead of Cloudflare IPv6 — e.g. suppress the Cloudflare
   AAAA for that host (disable IPv6 for it, or a dnsmasq/hosts override that
   covers v6), or point the substituter URL at the attic NetBird endpoint
   directly.

---

## Done when

Both fixed → an unpinned hass-pi toplevel dry-run on the box shows **everything
"will be fetched", nothing "will be built"** → remove the pin (the
`nixpkgs-rpi-kernel` input + the `boot.kernelPackages` override) → hass-pi
tracks the current kernel, fully build-free.
