# OpenDAP developer host tools (macOS). Install with: brew bundle --file=host/Brewfile
# Design applications (KiCad 10, FreeCAD 1.1, Blender 5.2) are installed from their official
# installers; host/setup.sh checks their versions.

# Repository hygiene
brew "git-lfs"
brew "pre-commit"
brew "reuse"
brew "yq"
brew "jq"
brew "gh"

# Python (per-study simulation environments)
brew "uv"

# Electronics simulation
brew "ngspice"

# Firmware: flashing, debugging, serial
brew "probe-rs-tools"
brew "picotool"
brew "dfu-util"
brew "openocd"
brew "tio"
brew "sigrok-cli"

# Rust tooling
brew "cargo-binstall"
# Linker for cross-builds to Blackbird OS against the image's glibc (cargo-zigbuild)
brew "zig"

# Emulation, and the Linux VM that builds images and the sysroot
brew "qemu"
brew "lima"
# LAN for virtual devices; bin/odap-vmnet install copies it to /opt/socket_vmnet as a root daemon
brew "socket_vmnet"
