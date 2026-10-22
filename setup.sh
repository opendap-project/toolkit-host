#!/bin/sh
# Set up an OpenDAP developer host (macOS). Safe to run again.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"

echo "== Homebrew packages"
brew bundle --file="$here/Brewfile"

echo "== Git LFS"
git lfs install --skip-repo

echo "== Rust targets"
# aarch64 Linux (OpenDAP OS, glibc and musl), Cortex-M0+ (STM32U0), Cortex-M33 and RISC-V (RP2350)
rustup target add aarch64-unknown-linux-gnu aarch64-unknown-linux-musl \
  thumbv6m-none-eabi thumbv8m.main-none-eabihf riscv32imac-unknown-none-elf

echo "== Rust cargo tools"
cargo binstall -y --locked cargo-nextest cargo-deny

echo "== KiCad"
kicad_cli="${KICAD_CLI:-/Applications/KiCad/KiCad.app/Contents/MacOS/kicad-cli}"
if [ -x "$kicad_cli" ]; then
  "$kicad_cli" version
  kicad_py="/Applications/KiCad/KiCad.app/Contents/Frameworks/Python.framework/Versions/Current/bin/python3"
  # Interactive HTML BOM runs inside KiCad's own Python, which provides pcbnew.
  "$kicad_py" -m pip install --quiet --upgrade "InteractiveHtmlBom==2.12.0"
else
  echo "KiCad 10 not found: install it from https://www.kicad.org/download/macos/" >&2
fi

echo "== Design applications"
for app in FreeCAD Blender; do
  plist="/Applications/$app.app/Contents/Info.plist"
  if [ -f "$plist" ]; then
    v="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$plist" 2>/dev/null || true)"
    [ -n "$v" ] || v="$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$plist" 2>/dev/null || echo unknown)"
    echo "$app $v"
  else
    echo "$app not found: install it from its official site" >&2
  fi
done

echo "== Done"
