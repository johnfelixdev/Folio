#!/bin/bash
# Builds Resources/AppIcon.icns from a 1024x1024 PNG.
#
# Uses iconutil and sips, both of which ship with the Command Line Tools.
# An asset catalog would need actool, which only ships with Xcode, and that
# dependency is not worth an icon.
set -euo pipefail

SOURCE="${1:-Scripts/icon-source.png}"
OUT_DIR="Sources/FolioApp/Resources"
ICONSET="$(mktemp -d)/AppIcon.iconset"

if [ ! -f "$SOURCE" ]; then
    echo "No hay icono de origen en $SOURCE. Genero uno provisional."
    mkdir -p "$(dirname "$SOURCE")"
    # A plain slate square, replaced whenever a real icon exists.
    python3 - "$SOURCE" <<'PY'
import struct, sys, zlib
path, size = sys.argv[1], 1024
row = b'\x00' + bytes([44, 48, 56, 255] * size)
raw = row * size
def chunk(tag, data):
    body = tag + data
    return struct.pack('>I', len(data)) + body + struct.pack('>I', zlib.crc32(body))
png = (b'\x89PNG\r\n\x1a\n'
       + chunk(b'IHDR', struct.pack('>IIBBBBB', size, size, 8, 6, 0, 0, 0))
       + chunk(b'IDAT', zlib.compress(raw))
       + chunk(b'IEND', b''))
open(path, 'wb').write(png)
PY
fi

mkdir -p "$ICONSET" "$OUT_DIR"
for size in 16 32 128 256 512; do
    sips -z $size $size "$SOURCE" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    sips -z $((size * 2)) $((size * 2)) "$SOURCE" \
        --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done

iconutil -c icns "$ICONSET" -o "$OUT_DIR/AppIcon.icns"
echo "Icono escrito en $OUT_DIR/AppIcon.icns"
