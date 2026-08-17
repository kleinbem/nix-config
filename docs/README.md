# NixOS Configuration Documentation Index

**Last Updated:** 2026-08-17

Quick navigation for the kleinbem fleet NixOS configuration.

---

## 🎯 Start Here

### For New Device Setup
1. **[DEVICE-TIERS.md](DEVICE-TIERS.md)** — Choose your tier, follow the template
   - Device tier definitions (Workstation, Edge Hub, Edge Node, Mobile)
   - Configuration checklist
   - Bootstrap instructions
   - Deployment strategy

### For Understanding Modules
2. **[MODULE-ORGANIZATION.md](MODULE-ORGANIZATION.md)** — Module import patterns explained
   - Three import strategies (Pattern A/B/C)
   - Module dependency graph
   - Common gotchas
   - When to use each pattern

### For CI/CD & Maintenance
3. **[../docs/MAINTENANCE-AUTOMATION.md](../docs/MAINTENANCE-AUTOMATION.md)** (in kleinbem repo)
   - Version pinning audit (`just audit-versions`)
   - Flake lock freshness check (`just check-flake-lock-age`)
   - Transitive dependency monitoring
   - Pre-commit hooks

---

## 📚 Full Documentation Map

### **Core Configuration** (Read These)

| File | Purpose | Status |
|------|---------|--------|
| [DEVICE-TIERS.md](DEVICE-TIERS.md) | Device tier definitions & setup checklist | ✅ Current (2026-08-17) |
| [MODULE-ORGANIZATION.md](MODULE-ORGANIZATION.md) | Module patterns & import strategies | ✅ Current (2026-08-17) |
| [CONTAINER-HOST-SETUP.md](CONTAINER-HOST-SETUP.md) | Container hosting module & setup | ✅ Current (2026-08-17) |
| [TROUBLESHOOTING.md](TROUBLESHOOTING.md) | Diagnostics for common issues | ✅ Current (2026-08-17) |
| [SECRETS-MANAGEMENT.md](SECRETS-MANAGEMENT.md) | Secure secrets with sops + age | ✅ Current (2026-08-17) |
| [IMPORTS.md](IMPORTS.md) | Module imports & flake structure | ✅ Active (2026-08-10) |
| [OPTIONS.md](OPTIONS.md) | Custom `my.*` option reference | ✅ Active (2026-08-10) |
| [SYSTEM_REFERENCE.md](SYSTEM_REFERENCE.md) | System-level config overview | ✅ Active (2026-08-10) |

### **Archive** (Completed/Superseded)

| File | Purpose | Status |
|------|---------|--------|
| homed_migration_plan.md | User directory migration planning | ✅ Completed |
| home_manager_gap_analysis.md | Home Manager coverage analysis | ✅ Completed |
| implementation_plan*.md | Task planning (various) | ⏸️ Historical |
| phone_deployment.md | Nix on Droid setup | ✅ Completed |
| PHASE1_STALWART.md | Stalwart email integration | 📅 In progress |
| PHASE3_AUTHENTIK.md | Authentik SSO deployment | 📅 Future |
| PHASE45_HRIS_COLLAB.md | HRIS/collaboration stack | 📅 Future |
| rpi-kernel-caching-followups.md | Raspberry Pi kernel caching | ✅ Completed |
| task.md, walkthrough*.md | Old planning docs | ⏸️ Historical |

---

## 🗂️ File Descriptions

### DEVICE-TIERS.md (387 lines)
**What:** Device tier definitions and setup requirements.

**Covers:**
- Tier definitions (Workstation, Edge Hub, Edge Node, Mobile)
- Required/recommended modules per tier
- Configuration checklist (what every device must have)
- Device template (copy-paste starting point)
- Deployment strategy (local vs SSH)
- Bootstrap instructions for new devices
- Current fleet status matrix

**Read when:** Setting up a new device, understanding tier architecture

**Example:** Want to add a new Edge Node? Go here first.

---

### MODULE-ORGANIZATION.md (380 lines)
**What:** Explanation of the three module import patterns in use.

**Covers:**
- Pattern A (Tier Bundle) — Recommended for new devices
- Pattern B (Selective Imports) — Used by mac-mini
- Pattern C (Aggregator) — Used by nixos-nvme
- Module layers (foundation, tier bundles, device-specific)
- Module dependency graph
- Common gotchas (undefined options, features not working)
- Recommended refactoring strategy (deferred)

**Read when:** Confused about module imports, adding modules to a device

**Example:** "Why doesn't audio work?" → Check MODULE-ORGANIZATION.md gotchas

---

### TROUBLESHOOTING.md (10 KB)
**What:** Diagnostic guide for common fleet issues.

**Covers:**
- Network connectivity (SSH, DNS)
- Storage/persistence (data loss, reboot issues)
- Build failures and performance
- Container issues
- Secrets & encryption
- Performance troubleshooting
- Debug checklist and issue reporting

**Read when:** Something breaks, system behaving oddly

---

### IMPORTS.md (9 KB)
**What:** Module imports and flake structure reference.

**Covers:**
- How nix-presets are imported
- Flake input organization
- Module name resolution
- Import order dependencies

**Read when:** Adding new dependencies, debugging import errors

---

### OPTIONS.md (9 KB)
**What:** Reference for custom `my.*` options defined in this fleet.

**Covers:**
- All custom options in `my.*` namespace
- Option types and defaults
- Where options are defined
- Which modules define which options

**Read when:** Trying to enable a feature, understanding available options

---

### SYSTEM_REFERENCE.md (6.5 KB)
**What:** System-level configuration overview.

**Covers:**
- Top-level flake.nix structure
- NixOS system outputs
- Device configuration entry points
- File organization

**Read when:** Understanding project structure, adding new devices

---

## 🔍 Quick Lookup

**"How do I add a new device?"**
→ DEVICE-TIERS.md (follow the tier, use the template)

**"Why does my module option not exist?"**
→ MODULE-ORGANIZATION.md (check imports)

**"What options are available?"**
→ OPTIONS.md (browse the reference)

**"How does the flake work?"**
→ SYSTEM_REFERENCE.md or IMPORTS.md

**"Why can't I find a module?"**
→ IMPORTS.md (trace the imports)

**"What's the current fleet status?"**
→ DEVICE-TIERS.md (status matrix at bottom)

**"How do I set up a container host?"**
→ CONTAINER-HOST-SETUP.md (new module for container hosting)

**"Something broke, where do I start?"**
→ TROUBLESHOOTING.md (diagnosis checklist, common issues)

**"How do I manage secrets securely?"**
→ SECRETS-MANAGEMENT.md (sops + age, rotation, integration)

---

## 📝 Contributing to Docs

### Keep These Updated
- **DEVICE-TIERS.md** — When adding/removing devices
- **MODULE-ORGANIZATION.md** — When module patterns change
- **This README** — When docs/README.md files are added/removed

### Archive Old Docs
- Move completed tasks to "Archive" section above
- Add status note (✅ Completed, ⏸️ Historical, etc.)
- Don't delete (useful for history)

### Write New Docs
- Keep it focused (one file per topic)
- Link to related docs
- Add to the map above
- Update this README

---

## 🚀 Next Steps

**Just deployed a new device?**
→ Update DEVICE-TIERS.md status matrix

**Found a gotcha?**
→ Add to MODULE-ORGANIZATION.md

**Need to document a pattern?**
→ Create a new file, add to map, update this README

---

**For maintenance automation, see:** kleinbem/docs/MAINTENANCE-AUTOMATION.md  
**For fleet infrastructure audit, see:** [FLEET-INFRA-AUDIT.md (in scratchpad)](../../docs/FLEET-INFRA-AUDIT.md)  
**For deployment workflow, see:** [DEVICE-TIERS.md → Deployment Strategy](DEVICE-TIERS.md#deployment-strategy)
