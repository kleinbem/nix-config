# `os dx::*` — developer experience (distrobox).

# Create a Fedora development distrobox.
create-fedora name="fedora-dev":
    distrobox create --image registry.fedoraproject.org/fedora:44 --name {{name}}

# Create an Ubuntu development distrobox.
create-ubuntu name="ubuntu-dev":
    distrobox create --image ubuntu:24.04 --name {{name}}

# Own home dir so host cargo/pnpm config and PATH don't leak into package tests.
# Create an Arch development distrobox for AUR packaging and testing.
create-arch name="arch-dev":
    distrobox create --image docker.io/library/archlinux:latest --name {{name}} \
        --home ~/.local/share/distrobox/{{name}}-home \
        --additional-packages "base-devel git namcap pacman-contrib"

# Enter a distrobox.
enter name="fedora-dev":
    distrobox enter {{name}}

# List all distroboxes.
list:
    distrobox list

# Update all distroboxes.
update:
    distrobox upgrade --all
