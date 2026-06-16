# Personas manifest — the canonical source of truth for every named
# principal that operates on the workspace. Each entry is consumed by:
#
#   - mailbox provisioning (Stalwart, Phase 1)
#   - DNS records (DKIM per persona, Phase 1)
#   - git commit author identity (via just jj::as <persona>)
#   - signing key registration (allowed_signers)
#   - Matrix / Synapse user creation (Phase 3)
#   - per-persona Qdrant collections (Phase 4)
#
# Adding a new persona = one attribute set here. All downstream
# provisioning reads from this file.
#
# Naming convention: persona key is the email local part (also used as
# the filesystem path under users/<name>/ and as the short identifier
# anywhere a single token is needed).

{
  michael = {
    full-name = "Michael Gruber";
    origin = "AT";
    timezone = "Europe/Vienna";
    email = "michael@kleinbem.dev";
    github-handle = "michael-gruber";
    tool = "claude-code";
    signing-key = "id_ed25519_michael";
  };

  thomas = {
    full-name = "Thomas Schmidt";
    origin = "DE";
    timezone = "Europe/Berlin";
    email = "thomas@kleinbem.dev";
    github-handle = "thomas-schmidt";
    tool = "aider";
    signing-key = "id_ed25519_thomas";
  };

  daniel = {
    full-name = "Daniel Meier";
    origin = "CH";
    timezone = "Europe/Zurich";
    email = "daniel@kleinbem.dev";
    github-handle = "daniel-meier";
    tool = "antigravity";
    signing-key = "id_ed25519_daniel";
  };

  rahul = {
    full-name = "Rahul Kumar";
    origin = "IN";
    timezone = "Asia/Kolkata";
    email = "rahul@kleinbem.dev";
    github-handle = "rahul-kumar";
    tool = "self-hosted-runner";
    signing-key = "id_ed25519_rahul";
  };

  juan = {
    full-name = "Juan González";
    origin = "AR";
    timezone = "America/Argentina/Buenos_Aires";
    email = "juan@kleinbem.dev";
    github-handle = "juan-gonzalez";
    tool = "gemini-cli";
    signing-key = "id_ed25519_juan";
  };
}
