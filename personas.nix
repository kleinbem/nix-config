# Personas manifest — PUBLIC layer.
#
# This file contains role/authorisation/operational data only.
# Personal identity (name, email, matrix-id, bio, location) lives in
# the PRIVATE `nix-secrets/personas-contact.nix` — kept out of the
# public repo for GDPR / privacy reasons (real human collaborators)
# and authenticity reasons (AI personas).
#
# Schema joined at lib-evaluation time by `lib/personas.nix`. If
# nix-secrets is not on the path, downstream views render with
# "(private)" placeholders.
#
# Per-persona public fields:
#
#   kind          "human" | "agent" — determines provisioning rules.
#   date-joined   ISO date.
#   signing-key   Filename in nix-secrets/personas/<key>/ (the
#                 filename itself is not sensitive; the private key
#                 inside IS, and lives encrypted in nix-secrets).
#   tool          "human" for humans; AI tool name for agents.
#   model         null for humans; specific LLM for agents.
#   role-tags     Capability tags consumed by authorization policy.
#                 Tags: founder, owner, operator, primary-driver,
#                 peer-reviewer, ui-specialist, ci-runner,
#                 experimental, trusted, can-touch-secrets,
#                 can-deploy.
#   active-hours  Operational window (used by scheduling). Not
#                 considered personal data — coarse-grained.

{
  # ─── Human operator(s) ────────────────────────────────────────────

  martin = {
    kind = "human";
    date-joined = "2025-01-01";
    signing-key = "id_ed25519_sk_rk_GitHubNoTouch";
    tool = "human";
    model = null;
    role-tags = [
      "founder"
      "owner"
      "operator"
      "trusted"
      "can-touch-secrets"
      "can-deploy"
    ];
    active-hours = "06-22";
  };

  # ─── AI agents ────────────────────────────────────────────────────

  michael = {
    kind = "agent";
    date-joined = "2026-06-16";
    signing-key = "id_ed25519_michael";
    tool = "claude-code";
    model = "claude-opus-4-7";
    role-tags = [
      "primary-driver"
      "trusted"
      "can-touch-secrets"
      "can-deploy"
    ];
    active-hours = "08-18";
  };

  thomas = {
    kind = "agent";
    date-joined = "2026-06-16";
    signing-key = "id_ed25519_thomas";
    tool = "aider";
    model = "claude-sonnet-4-6";
    role-tags = [
      "peer-reviewer"
      "trusted"
    ];
    active-hours = "09-17";
  };

  daniel = {
    kind = "agent";
    date-joined = "2026-06-16";
    signing-key = "id_ed25519_daniel";
    tool = "antigravity";
    model = "claude-opus-4-7";
    role-tags = [
      "ui-specialist"
      "trusted"
    ];
    active-hours = "09-18";
  };

  rahul = {
    kind = "agent";
    date-joined = "2026-06-16";
    signing-key = "id_ed25519_rahul";
    tool = "self-hosted-runner";
    model = "claude-haiku-4-5-20251001";
    role-tags = [
      "ci-runner"
    ];
    active-hours = "00-23";
  };

  juan = {
    kind = "agent";
    date-joined = "2026-06-16";
    signing-key = "id_ed25519_juan";
    tool = "gemini-cli";
    model = "gemini-2.5-pro";
    role-tags = [
      "experimental"
    ];
    active-hours = "10-19";
  };
}
