#!/bin/bash
# Печатает имя файла DMG — Clepsydra-<версия>.dmg.
#
# Версия — человеческая, CFBundleShortVersionString из Resources/Info.plist:
# в скрипте её нет, иначе имя разошлось бы с тем, что показывает «О программе».
#
#   ./Tools/dmg-name.sh                 версия — из Resources/Info.plist
#   ./Tools/dmg-name.sh путь/Info.plist plist приходит снаружи, для тестов
set -euo pipefail
cd "$(dirname "$0")/.."

PLIST="${1:-Resources/Info.plist}"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST" 2>/dev/null || true)"

if [[ -z "$VERSION" ]]; then
    echo "ОШИБКА: в $PLIST нет CFBundleShortVersionString." >&2
    exit 1
fi

echo "Clepsydra-$VERSION.dmg"
