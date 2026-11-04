import 'common.just'

set working-directory := ".."

# --- nix-config maintenance ---
# Workspace-level concerns (treefmt, cross-repo audits, GC, knowledge mgmt, …)
# stay in the meta-workspace `.just/maintenance.just`.



[group("Cleanup")]
clean-launchers *args:
    @echo "🚀 Cleaning broken launchers..."
    @bash ./scripts/clean-launchers.sh {{args}}
