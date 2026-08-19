# `os notes::*` — Obsidian vault helpers.

SCRIPTS := "~/Develop/github.com/kleinbem/nix-config/users/martin/files/scripts"

# Append a quick note to the Obsidian Inbox.
add message="":
    @echo "📝 Capturing note..."
    @echo "- [ ] {{message}} (Captured on $(date))" >> $HOME/Documents/Notes/Inbox.md

# Launch Obsidian in the background.
open:
    @obsidian &

# Run the Obsidian vault organizer (Nushell script): PARA foldering,
# flags Areas/Resources notes overdue for distillation (CODE workflow),
# and regenerates AGENTS.md — the vault's LLM orientation file.
organize:
    @nu {{SCRIPTS}}/organize-notes.nu

# Vault integrity check.
check:
    @echo "🏠 Checking vault integrity..."
    @bash {{SCRIPTS}}/vault-health.sh

# Symlink the workspace docs/ + each repo's knowledge bases into Obsidian.
link-docs:
    @bash {{SCRIPTS}}/link-docs-to-obsidian.sh
