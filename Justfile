# DEPRECATED: Use the root Justfile instead
# This shim redirects common maintenance commands to the master workspace Justfile

default:
    @just --list --justfile ../justfile

# Redirect all commands to root
%:
    @echo "🔄 Redirecting to workspace root Justfile..."
    @just --justfile ../justfile {{arg(0)}} {{stack_args()}}
