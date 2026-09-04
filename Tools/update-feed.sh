#!/bin/bash
# Печатает фид обновлений — то, по чему установленные копии узнают о новом
# выпуске. Кладётся в релиз файлом; почему так — в
# docs/adr/0009-updates-are-checked-quietly.md.
#
# Адрес фида постоянный: releases/latest/download/<имя>. Поэтому имя от релиза
# к релизу не меняется — как и у образа, на который ведёт «Установка» в README.
#
#   ./Tools/update-feed.sh --name                        имя файла в релизе
#   ./Tools/update-feed.sh 1.1 20260904105921 docs/releases/1.1.md
#   ./Tools/update-feed.sh 1.1 20260904105921 файл 2026-09-04T10:59:21Z
#                                                дата снаружи, для тестов
set -euo pipefail
cd "$(dirname "$0")/.."

FEED_NAME=updates.json

# Имя в коде — UpdateFeed.fileName; из него приложение собирает адрес фида.
if [[ "${1:-}" == "--name" ]]; then
    echo "$FEED_NAME"
    exit 0
fi

VERSION="${1:-}"
BUILD="${2:-}"
CHANGES="${3:-}"
PUBLISHED="${4:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}"

# Букву v пишут и не пишут — как в Tools/release-tag.sh, где живёт сам тег.
VERSION="${VERSION#v}"

if [[ -z "$VERSION" ]]; then
    echo "ОШИБКА: не названа версия выпуска." >&2
    exit 1
fi

# Сравнивают установленные копии по CFBundleVersion, а он число: строка вместо
# номера оставила бы их без обновления молча.
if [[ -z "$BUILD" || -n "${BUILD//[0-9]/}" ]]; then
    echo "ОШИБКА: номер сборки «$BUILD» — не число." >&2
    exit 1
fi

if [[ -z "$CHANGES" || ! -f "$CHANGES" ]]; then
    echo "ОШИБКА: нет файла с описанием изменений: ${CHANGES:-не назван}." >&2
    exit 1
fi

if [[ -z "$(tr -d '[:space:]' < "$CHANGES")" ]]; then
    echo "ОШИБКА: в $CHANGES пусто — выпуск без «что изменилось» никому не нужен." >&2
    exit 1
fi

# Адрес архива обновления — тот файл, который разворачивает установщик, а не
# образ. Собирает адрес Tools/release-asset-url.sh, один на оба фида: тот же
# адрес стоит в фиде установщика, и разойтись им негде.
ARCHIVE="$(./Tools/release-asset-url.sh "$VERSION" "$(./Tools/update-archive.sh --name)")"

# Описание пишется руками, а в JSON попадает строкой: кавычки, косые, табуляции
# и переносы экранируются, иначе фид не разберётся и обновления никто не увидит.
NOTES="$(
    sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e $'s/\t/\\\\t/g' -e 's/\r$//' "$CHANGES" \
        | awk '{ printf "%s\\n", $0 }'
)"

cat <<JSON
{
  "version": "$VERSION",
  "build": "$BUILD",
  "archive": "$ARCHIVE",
  "published": "$PUBLISHED",
  "notes": "$NOTES"
}
JSON
