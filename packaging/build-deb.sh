#!/bin/sh
# Build dist/canon-scan-to-pc_<version>_all.deb for Debian, Ubuntu, Linux Mint and friends.
# Needs only dpkg-deb (and lintian, optionally, to check the result).
set -eu
umask 022

ROOT=$(cd "$(dirname "$0")/.." && pwd)
VERSION=$(sed -n 's/^__version__ = "\(.*\)"$/\1/p' "$ROOT/canon-scan-to-pc")
PKG=canon-scan-to-pc
OUT="$ROOT/dist/${PKG}_${VERSION}_all.deb"
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
chmod 755 "$STAGE"
DOC="$STAGE/usr/share/doc/$PKG"

install -D -m 755 "$ROOT/canon-scan-to-pc" "$STAGE/usr/bin/canon-scan-to-pc"
install -D -m 755 "$ROOT/canon-scan-to-pc-settings" "$STAGE/usr/bin/canon-scan-to-pc-settings"
install -D -m 644 "$ROOT/canon-scan-to-pc-settings.desktop" \
    "$STAGE/usr/share/applications/canon-scan-to-pc-settings.desktop"
mkdir -p "$STAGE/usr/lib/systemd/user"
sed 's|^ExecStart=.*|ExecStart=/usr/bin/canon-scan-to-pc|' "$ROOT/canon-scan-to-pc.service" \
    > "$STAGE/usr/lib/systemd/user/canon-scan-to-pc.service"
chmod 644 "$STAGE/usr/lib/systemd/user/canon-scan-to-pc.service"

for page in canon-scan-to-pc canon-scan-to-pc-settings; do
    mkdir -p "$STAGE/usr/share/man/man1"
    gzip -9n < "$ROOT/man/$page.1" > "$STAGE/usr/share/man/man1/$page.1.gz"
    chmod 644 "$STAGE/usr/share/man/man1/$page.1.gz"
done
install -D -m 644 "$ROOT/README.md" "$DOC/README.md"
install -D -m 644 "$ROOT/config.ini" "$DOC/config.ini.example"
cat > "$DOC/copyright" <<COPYRIGHT
Format: https://www.debian.org/doc/packaging-manuals/copyright-format/1.0/
Upstream-Name: canon-scan-to-pc
Source: https://github.com/anthonytheinventor/canon-scan-to-pc

Files: *
Copyright: 2026 anthonytheinventor
License: MIT
$(sed -n '5,$p' "$ROOT/LICENSE" | sed 's/^$/./; s/^/ /')
COPYRIGHT
printf '%s (%s) unstable; urgency=medium\n\n  * Release %s. Changes: see the commit history on GitHub.\n\n -- anthonytheinventor <298878686+anthonytheinventor@users.noreply.github.com>  %s\n' \
    "$PKG" "$VERSION" "$VERSION" "$(date -R)" | gzip -9n > "$DOC/changelog.gz"
chmod 644 "$DOC/copyright" "$DOC/changelog.gz"

mkdir -p "$STAGE/DEBIAN"
cat > "$STAGE/DEBIAN/control" <<CONTROL
Package: $PKG
Version: $VERSION
Section: graphics
Priority: optional
Architecture: all
Depends: python3 (>= 3.8), sane-utils, libsane1, python3-pil
Recommends: avahi-utils, python3-gi, gir1.2-gtk-3.0, libnotify-bin, xdg-utils, dbus
Installed-Size: $(du -sk --exclude=DEBIAN "$STAGE" | cut -f1)
Maintainer: anthonytheinventor <298878686+anthonytheinventor@users.noreply.github.com>
Homepage: https://github.com/anthonytheinventor/canon-scan-to-pc
Description: Scan → Computer from Canon imageCLASS / i-SENSYS printers on Linux
 Makes this computer appear in a Canon imageCLASS or i-SENSYS printer's
 "Scan → Computer" list, like Canon's Windows-only MF Scan Utility does, and
 saves scans started at the printer to ~/Scans as PDF, PNG or JPEG.
 .
 After installing, open "Canon Scan to PC" from the applications menu, turn on
 "Start at login" and press Save. Uses SANE's pixma backend for the scan itself.
CONTROL

mkdir -p "$ROOT/dist"
/usr/bin/dpkg-deb --root-owner-group -Zxz --build "$STAGE" "$OUT" >/dev/null
echo "$OUT"
