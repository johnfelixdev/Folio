#!/bin/bash
# Builds Folio.app from the SwiftPM executable.
#
# Deliberately free of any Xcode-only tool, so this runs with nothing but the
# Command Line Tools and never needs DEVELOPER_DIR.
set -euo pipefail

CONFIG="${1:-release}"
APP="build/Folio.app"
CONTENTS="$APP/Contents"

echo "==> Compilando ($CONFIG)"
swift build -c "$CONFIG" --product FolioApp

BINARY="$(swift build -c "$CONFIG" --product FolioApp --show-bin-path)/FolioApp"
if [ ! -x "$BINARY" ]; then
    echo "No se encontró el ejecutable en $BINARY" >&2
    exit 1
fi

if [ ! -f "Sources/FolioApp/Resources/AppIcon.icns" ]; then
    echo "==> Generando icono"
    ./Scripts/make-icon.sh
fi

echo "==> Montando el bundle"
rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
cp "$BINARY" "$CONTENTS/MacOS/FolioApp"
cp "Sources/FolioApp/Resources/Info.plist" "$CONTENTS/Info.plist"
cp "Sources/FolioApp/Resources/AppIcon.icns" "$CONTENTS/Resources/AppIcon.icns"

# SwiftPM puts a resource bundle beside the binary; the app needs it inside.
BIN_DIR="$(dirname "$BINARY")"
for bundle in "$BIN_DIR"/*.bundle; do
    [ -e "$bundle" ] && cp -R "$bundle" "$CONTENTS/Resources/"
done

echo "==> Firmando (ad-hoc, uso local)"
codesign --force --deep --sign - \
    --entitlements "Sources/FolioApp/Resources/Folio.entitlements" \
    "$APP"

echo "==> Verificando"
codesign --verify --verbose "$APP"
plutil -lint "$CONTENTS/Info.plist"

echo "Listo: $APP"
echo "Ábrelo con:  open $APP"
