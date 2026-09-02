#!/bin/bash
# Собирает Resources/Clepsydra.icns из Resources/icon-source.png (1024×1024, с прозрачностью).
#
#   ./Tools/make-icns.sh
#
# Каждый размер лежит в .icns отдельной картинкой, поэтому все они пересчитываются
# из мастера, а не давятся друг из друга.
set -euo pipefail
cd "$(dirname "$0")/.."

SRC=Resources/icon-source.png
SET=$(mktemp -d)/Clepsydra.iconset
mkdir -p "$SET"

emit() { sips -z "$2" "$2" "$SRC" --out "$SET/icon_$1.png" >/dev/null; }

emit 16x16       16
emit 16x16@2x    32
emit 32x32       32
emit 32x32@2x    64
emit 128x128    128
emit 128x128@2x 256
emit 256x256    256
emit 256x256@2x 512
emit 512x512    512
emit 512x512@2x 1024

iconutil -c icns "$SET" -o Resources/Clepsydra.icns
rm -rf "$(dirname "$SET")"
echo "готово: Resources/Clepsydra.icns ($(du -h Resources/Clepsydra.icns | cut -f1))"
