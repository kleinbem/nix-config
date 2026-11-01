# Personas manifest, public layer: roles and operational data only.
# Identity (name, email, bio...) stays private in the sops-encrypted
# kleinbem-secrets/personas/contact.nix; lib/personas.nix joins the two and
# shows "(private)" when it can't decrypt.
#
# Fields:
#   kind          "human" | "agent"; decides provisioning.
#   date-joined   ISO date.
#   signing-key   Label for assertUniqueSigningKeys only; the real key is
#                 always `id_ed25519` in kleinbem-secrets/personas/<name>.yaml.
#   tool          "human", or the agent's AI tool.
#   model         null for humans, the LLM for agents.
#   role-tags     Authorization tags: founder, owner, operator, primary-driver,
#                 peer-reviewer, ui-specialist, ci-runner, experimental,
#                 trusted, can-touch-secrets, can-deploy.
#   active-hours  Operational window for scheduling.

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

  michael-gruber = {
    kind = "agent";
    date-joined = "2026-06-16";
    signing-key = "id_ed25519_michael-gruber";
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

  thomas-schmidt = {
    kind = "agent";
    date-joined = "2026-06-16";
    signing-key = "id_ed25519_thomas-schmidt";
    tool = "aider";
    model = "claude-sonnet-4-6";
    role-tags = [
      "peer-reviewer"
      "trusted"
    ];
    active-hours = "09-17";
  };

  daniel-meier = {
    kind = "agent";
    date-joined = "2026-06-16";
    signing-key = "id_ed25519_daniel-meier";
    tool = "antigravity";
    model = "claude-opus-4-7";
    role-tags = [
      "ui-specialist"
      "trusted"
    ];
    active-hours = "09-18";
  };

  rahul-kumar = {
    kind = "agent";
    date-joined = "2026-06-16";
    signing-key = "id_ed25519_rahul-kumar";
    tool = "self-hosted-runner";
    model = "claude-haiku-4-5-20251001";
    role-tags = [
      "ci-runner"
    ];
    active-hours = "00-23";
  };

  juan-gonzalez = {
    kind = "agent";
    date-joined = "2026-06-16";
    signing-key = "id_ed25519_juan-gonzalez";
    tool = "gemini-cli";
    model = "gemini-2.5-pro";
    role-tags = [
      "experimental"
    ];
    active-hours = "10-19";
  };
}
