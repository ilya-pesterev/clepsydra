#!/bin/bash
# Печатает фид установщика — то, по чему Sparkle скачивает и ставит выпуск.
# Кладётся в релиз файлом рядом с фидом из docs/adr/0009-updates-are-checked-quietly.md;
# почему их два, а не один — в docs/adr/0010-update-installs-itself.md.
#
#   ./Tools/update-installer-feed.sh --name                        имя файла в релизе
#   ./Tools/update-installer-feed.sh 1.1 20260904105921 Clepsydra.zip
#
# Адрес постоянный: releases/latest/download/<имя>, как у фида и у образа.
# Поэтому имя от релиза к релизу не меняется.
#
# Описания выпуска здесь нет намеренно: окна с «что изменилось» приложение не
# показывает (ADR-0009), и держать второй список изменений — значит однажды
# разойтись с первым. Что изменилось живёт в фиде и на странице релиза.
set -euo pipefail
cd "$(dirname "$0")/.."

FEED_NAME=updates.xml

# Имя стоит в SUFeedURL бандла; прогон сверяет, что это одна строка.
if [[ "${1:-}" == "--name" ]]; then
    echo "$FEED_NAME"
    exit 0
fi

VERSION="${1:-}"
BUILD="${2:-}"
ARCHIVE="${3:-}"

# Букву v пишут и не пишут — как в Tools/release-tag.sh.
VERSION="${VERSION#v}"

if [[ -z "$VERSION" ]]; then
    echo "ОШИБКА: не названа версия выпуска." >&2
    exit 1
fi

# Сравнивает установленную сборку с выпущенной сама Sparkle, и сравнивает
# числом: строка вместо номера оставила бы копии без обновления молча.
if [[ -z "$BUILD" || -n "${BUILD//[0-9]/}" ]]; then
    echo "ОШИБКА: номер сборки «$BUILD» — не число." >&2
    exit 1
fi

if [[ -z "$ARCHIVE" || ! -f "$ARCHIVE" ]]; then
    echo "ОШИБКА: нет архива обновления: ${ARCHIVE:-не назван}." >&2
    exit 1
fi

# Подпись EdDSA — единственная опора доверия: подпись бандла ad-hoc, и
# проверить её установщику не по чему. Ключ живёт в связке ключей автора.
SIGNATURE="$(./Tools/sign-update.swift "$ARCHIVE")"
LENGTH="$(stat -f%z "$ARCHIVE")"

# Нижняя граница системы — из того же Info.plist, что и у бандла: разойдись
# они, обновление предложилось бы Mac, на котором не запустится.
MINIMUM="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' Resources/Info.plist)"

# Адрес собирает тот же скрипт, что и для фида приложения: два фида на один
# выпуск, и указывать они обязаны на один файл.
ADDRESS="$(./Tools/release-asset-url.sh "$VERSION" "$(./Tools/update-archive.sh --name)")"

cat <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Clepsydra</title>
    <item>
      <title>$VERSION</title>
      <sparkle:version>$BUILD</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>$MINIMUM</sparkle:minimumSystemVersion>
      <enclosure url="$ADDRESS"
                 length="$LENGTH"
                 type="application/octet-stream"
                 sparkle:edSignature="$SIGNATURE" />
    </item>
  </channel>
</rss>
XML
