#!/bin/bash
# Печатает имя файла DMG. Имён два, и разные они не по недосмотру:
#
#   Clepsydra-<версия>.dmg  собранный рядом с бандлом — версия в имени, чтобы
#                           скачанный файл говорил, что он такое;
#   Clepsydra.dmg           выложенный в релиз — без версии, потому что ссылка
#                           в README ведёт на releases/latest/download/<имя>,
#                           и одноразовой её делать нельзя: с выходом 1.1
#                           ссылка на Clepsydra-1.0.dmg отдала бы 404.
#
# Версия — человеческая, CFBundleShortVersionString из Resources/Info.plist:
# в скрипте её нет, иначе имя разошлось бы с тем, что показывает «О программе».
#
#   ./Tools/dmg-name.sh                 версия — из Resources/Info.plist
#   ./Tools/dmg-name.sh --published     имя, под которым образ лежит в релизе
#   ./Tools/dmg-name.sh путь/Info.plist plist приходит снаружи, для тестов
set -euo pipefail
cd "$(dirname "$0")/.."

# Релизное имя версии не знает — и plist ему не нужен.
if [[ "${1:-}" == "--published" ]]; then
    echo "Clepsydra.dmg"
    exit 0
fi

PLIST="${1:-Resources/Info.plist}"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST" 2>/dev/null || true)"

if [[ -z "$VERSION" ]]; then
    echo "ОШИБКА: в $PLIST нет CFBundleShortVersionString." >&2
    exit 1
fi

echo "Clepsydra-$VERSION.dmg"
