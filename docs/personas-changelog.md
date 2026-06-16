# Personas Changelog

Append-only audit log of persona lifecycle transitions. Newest at top.
Future entries will be added automatically by `just personas::{activate,probation,leave,resume,retire,purge}` recipes (Tier 3, not yet implemented).

Format: `YYYY-MM-DD` heading per day, bullet per event.

---

## 2026-06-16

- **Schema extended**: identity now includes `model`, `role-tags`, `active-hours`, `bio`, `matrix-id`, `oidc-subject`, `date-joined`. Lifecycle state moved to `personas-state.nix`. Voice files at `users/<name>/voice.md`.
- **Daniel Meier** onboarded (status: `active`, tool: `antigravity`, role: `ui-specialist`+`trusted`, origin: 🇨🇭 CH).
- **Juan González** onboarded (status: `active`, tool: `gemini-cli`, role: `experimental`, origin: 🇦🇷 AR).
- **Michael Gruber** onboarded (status: `active`, tool: `claude-code`, role: `primary-driver`+`trusted`+`can-touch-secrets`+`can-deploy`, origin: 🇦🇹 AT).
- **Rahul Kumar** onboarded (status: `active`, tool: `self-hosted-runner`, role: `ci-runner`, origin: 🇮🇳 IN). No human backup — CI persona.
- **Thomas Schmidt** onboarded (status: `active`, tool: `aider`, role: `peer-reviewer`+`trusted`, origin: 🇩🇪 DE).
