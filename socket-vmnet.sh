#!/bin/sh
# Give the virtual T1 a NIC on this Mac's network (blackbird-os OS-034): install socket_vmnet as a
# root-owned launchd daemon bridged to the interface of the default route. Run once; safe to re-run.
# Usage: socket-vmnet.sh [install|uninstall|status]
#
# The binaries are copied to /opt/socket_vmnet (owned by root) instead of running Homebrew's copy as
# root, because the Homebrew prefix is writable by the user (Lima's guidance for socket_vmnet).
set -eu
[ "$(uname -s)" = Darwin ] || { echo "macOS only: on Linux, bridge a tap device instead" >&2; exit 2; }
iface="${DAP_LAN_INTERFACE:-$(route -n get default 2>/dev/null | awk '/interface:/{print $2}')}"
label="org.opendap.socket_vmnet.bridged.$iface"
plist="/Library/LaunchDaemons/$label.plist"
sock="/var/run/socket_vmnet.bridged.$iface"

case "${1:-install}" in
  install)
    [ -n "$iface" ] || { echo "no default-route interface; set DAP_LAN_INTERFACE" >&2; exit 1; }
    brew list socket_vmnet >/dev/null 2>&1 || brew install socket_vmnet
    src="$(brew --prefix socket_vmnet)/bin"
    sudo mkdir -p /opt/socket_vmnet/bin
    sudo install -o root -g wheel -m 0755 "$src/socket_vmnet" "$src/socket_vmnet_client" /opt/socket_vmnet/bin/
    sudo tee "$plist" >/dev/null <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>$label</string>
  <key>ProgramArguments</key><array>
    <string>/opt/socket_vmnet/bin/socket_vmnet</string>
    <string>--vmnet-mode=bridged</string>
    <string>--vmnet-interface=$iface</string>
    <string>--socket-group=staff</string>
    <string>$sock</string>
  </array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>StandardErrorPath</key><string>/var/log/socket_vmnet.bridged.$iface.log</string>
</dict></plist>
PLIST
    sudo chown root:wheel "$plist"
    sudo launchctl bootout system "$plist" 2>/dev/null || true
    sudo launchctl bootstrap system "$plist"
    sleep 1
    [ -S "$sock" ] && echo "socket_vmnet bridged to $iface: $sock" || { echo "socket_vmnet did not start; see /var/log/socket_vmnet.bridged.$iface.log" >&2; exit 1; };;
  uninstall)
    sudo launchctl bootout system "$plist" 2>/dev/null || true
    sudo rm -f "$plist" "$sock"
    echo "removed $label (the binaries stay in /opt/socket_vmnet)";;
  status)
    if [ -S "$sock" ]; then echo "running: $sock"; else echo "not running ($sock missing)"; fi;;
  *) echo "usage: $0 [install|uninstall|status]" >&2; exit 2;;
esac
