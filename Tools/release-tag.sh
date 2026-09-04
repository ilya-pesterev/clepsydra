#!/bin/bash
# Печатает имя тега релиза — v<версия> — и заодно сверяет названную версию
# с той, что уйдёт в бандл.
#
# Версию называет человек, а не берёт молча plist: иначе сверять было бы не с
# чем. Релиз v1.0 с бандлом версии 0.9 — это страница, которая обещает одно,
# а «О программе» показывает другое.
#
#   ./Tools/release-tag.sh 1.0                  версия бандла — из Resources/Info.plist
#   ./Tools/release-tag.sh 1.0 путь/Info.plist  plist приходит снаружи, для тестов
set -euo pipefail
cd "$(dirname "$0")/.."

ASKED_VERSION="${1:-}"
PLIST="${2:-Resources/Info.plist}"

if [[ -z "$ASKED_VERSION" ]]; then
    echo "ОШИБКА: не названа версия релиза, напр. ./release.sh 1.0." >&2
    exit 1
fi

# Букву v пишут и не пишут — тег всё равно один.
ASKED_VERSION="${ASKED_VERSION#v}"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST" 2>/dev/null || true)"

if [[ -z "$VERSION" ]]; then
    echo "ОШИБКА: в $PLIST нет CFBundleShortVersionString." >&2
    exit 1
fi

if [[ "$ASKED_VERSION" != "$VERSION" ]]; then
    echo "ОШИБКА: просят релиз $ASKED_VERSION, а в бандле версия $VERSION." >&2
    echo "Поправьте CFBundleShortVersionString в $PLIST или назовите версию бандла." >&2
    exit 1
fi

echo "v$VERSION"
