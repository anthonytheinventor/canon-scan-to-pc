#!/bin/sh
# Install canon-scan-to-pc for the current user (no root needed), or remove it with --uninstall.
# (On Debian, Ubuntu and Mint you can install the .deb from the Releases page instead.)
set -eu

BIN_DIR="$HOME/.local/bin"
BIN="$BIN_DIR/canon-scan-to-pc"
GUI="$BIN_DIR/canon-scan-to-pc-settings"
APPS="$HOME/.local/share/applications"
DESKTOP="$APPS/canon-scan-to-pc-settings.desktop"
CONF_DIR="$HOME/.config/canon-scan-to-pc"
UNIT_DIR="$HOME/.config/systemd/user"
UNIT="$UNIT_DIR/canon-scan-to-pc.service"
HERE=$(cd "$(dirname "$0")" && pwd)

if [ "${1:-}" = "--uninstall" ]; then
    systemctl --user disable --now canon-scan-to-pc 2>/dev/null || true
    rm -f "$BIN" "$GUI" "$DESKTOP" "$UNIT"
    systemctl --user daemon-reload
    echo "Removed. Your settings are still in $CONF_DIR and your scans in ~/Scans."
    exit 0
fi

missing=""
command -v scanimage >/dev/null || missing="$missing sane-utils"
python3 -c 'import PIL' 2>/dev/null || missing="$missing python3-pil"
if [ -n "$missing" ]; then
    echo "Missing packages:$missing"
    echo "On Debian, Ubuntu or Mint:  sudo apt install$missing"
    exit 1
fi
if ! command -v avahi-browse >/dev/null; then
    echo "Note: avahi-browse (package avahi-utils) isn't installed, so the printer can't be"
    echo "found automatically. Install it, or set the printer in the settings window."
fi
if ! python3 -c 'import gi; gi.require_version("Gtk", "3.0")' 2>/dev/null; then
    echo "Note: the settings window needs python3-gi and gir1.2-gtk-3.0."
fi

mkdir -p "$BIN_DIR" "$CONF_DIR" "$UNIT_DIR" "$APPS"
install -m 755 "$HERE/canon-scan-to-pc" "$BIN"
install -m 755 "$HERE/canon-scan-to-pc-settings" "$GUI"
# The menu entry needs the full path: ~/.local/bin isn't always on a launcher's PATH.
sed "s|^Exec=.*|Exec=$GUI|" "$HERE/canon-scan-to-pc-settings.desktop" > "$DESKTOP"
if [ -e "$CONF_DIR/config.ini" ]; then
    echo "Keeping your existing $CONF_DIR/config.ini"
else
    install -m 644 "$HERE/config.ini" "$CONF_DIR/config.ini"
fi
install -m 644 "$HERE/canon-scan-to-pc.service" "$UNIT"
systemctl --user daemon-reload

if command -v avahi-browse >/dev/null; then
    echo "Looking for Canon scanners on the network..."
    "$BIN" --discover || echo "None found yet. Is the printer on? You can set it in the settings window."
fi

systemctl --user enable canon-scan-to-pc
systemctl --user restart canon-scan-to-pc     # starts it, or picks up a newer version
echo
echo "Installed and running. Settings: \"Canon Scan to PC\" in your applications menu."
echo "On the printer: Scan > Computer > pick this computer > Start. Scans go to ~/Scans."
