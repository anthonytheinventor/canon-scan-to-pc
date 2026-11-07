#!/bin/sh
# Install canon-scan-to-pc for the current user (no root needed), or remove it with --uninstall.
set -eu

BIN="$HOME/.local/bin/canon-scan-to-pc"
CONF_DIR="$HOME/.config/canon-scan-to-pc"
UNIT_DIR="$HOME/.config/systemd/user"
UNIT="$UNIT_DIR/canon-scan-to-pc.service"
HERE=$(cd "$(dirname "$0")" && pwd)

if [ "${1:-}" = "--uninstall" ]; then
    systemctl --user disable --now canon-scan-to-pc 2>/dev/null || true
    rm -f "$BIN" "$UNIT"
    systemctl --user daemon-reload
    echo "Removed. Your settings are still in $CONF_DIR and your scans in ~/Scans."
    exit 0
fi

missing=""
command -v scanimage >/dev/null || missing="$missing sane-utils"
python3 -c 'import PIL' 2>/dev/null || missing="$missing python3-pil"
command -v avahi-browse >/dev/null || missing="$missing avahi-utils"
if [ -n "$missing" ]; then
    echo "Missing packages:$missing"
    echo "On Debian, Ubuntu or Mint:  sudo apt install$missing"
    echo "(avahi-utils is only needed to find the printer automatically)"
    exit 1
fi

mkdir -p "$(dirname "$BIN")" "$CONF_DIR" "$UNIT_DIR"
install -m 755 "$HERE/canon-scan-to-pc" "$BIN"
if [ -e "$CONF_DIR/config.ini" ]; then
    echo "Keeping your existing $CONF_DIR/config.ini"
else
    install -m 644 "$HERE/config.ini" "$CONF_DIR/config.ini"
fi
install -m 644 "$HERE/canon-scan-to-pc.service" "$UNIT"
systemctl --user daemon-reload

echo "Looking for Canon scanners on the network..."
"$BIN" --discover || echo "None found yet. Is the printer on? You can set host in $CONF_DIR/config.ini."

systemctl --user enable --now canon-scan-to-pc
echo
echo "Installed and running. On the printer: Scan > Computer > pick this computer > Start."
echo "Scans are saved to ~/Scans. Log:  journalctl --user -u canon-scan-to-pc -f"
