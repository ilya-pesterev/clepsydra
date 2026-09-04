#!/bin/bash
# Печатает, сколько картинок доехало до бандла, и говорит кодом возврата,
# доехали ли все.
#
# Портретов философов и фотографий для режима Стетхема в репозитории нет:
# права на снимки не наши, и бандл собирается с машины, где они лежат.
# Поэтому сборка без картинок собирается молча — и сказать об этом вслух
# должен кто-то один, общий для сборки и для выпуска.
#
#   ./Tools/bundle-pictures.sh Clepsydra.app
#
# Код возврата: 0 — всё на месте, 2 — что-то не доехало (для ./build.sh это
# не отказ, для ./release.sh — повод переспросить), 1 — бандла нет.
set -euo pipefail
cd "$(dirname "$0")/.."

APP="${1:-}"

if [[ -z "$APP" || ! -d "$APP" ]]; then
    echo "ОШИБКА: нет бандла ${APP:-— он не назван}." >&2
    exit 1
fi

# Точечные файлы не картинки: заглянувший в папку Finder оставляет .DS_Store,
# и считать его портретом — обманывать себя перед самым релизом.
count_pictures() {
    if [[ ! -d "$1" ]]; then echo 0; return; fi
    find "$1" -type f ! -name '.*' | wc -l | tr -d ' '
}

PORTRAITS="$(count_pictures "$APP/Contents/Resources/philosophers")"
STATHAM="$(count_pictures "$APP/Contents/Resources/statham")"

echo "    портретов философов: $PORTRAITS"
echo "    фотографий для режима Стетхема: $STATHAM"

MISSING=false

if [[ "$PORTRAITS" == 0 ]]; then
    echo "    философский режим покажет цитату без портрета"
    MISSING=true
fi

if [[ "$STATHAM" == 0 ]]; then
    echo "    режим Стетхема покажет наклейки без фигуры"
    MISSING=true
fi

if [[ "$MISSING" == true ]]; then exit 2; fi
