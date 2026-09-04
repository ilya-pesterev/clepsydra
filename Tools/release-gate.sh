#!/bin/bash
# Ворота релиза: пропускают выпуск, только если номер сборки больше номера
# прошлого релиза.
#
# Не выросший номер значит, что часы на машине сбились: обновление такой релиз
# никому не покажет — установленные копии сравнивают версии по CFBundleVersion,
# а не по человеческой строке.
#
#   ./Tools/release-gate.sh 20260904153012              сверяет с last-release-build
#   ./Tools/release-gate.sh 20260904153012 путь/к/файлу файл приходит снаружи, для тестов
set -euo pipefail
cd "$(dirname "$0")/.."

BUILD="${1:-}"
LAST_RELEASE_FILE="${2:-last-release-build}"

if [[ -z "$BUILD" ]]; then
    echo "ОШИБКА: не назван номер сборки." >&2
    exit 1
fi

if [[ ! -f "$LAST_RELEASE_FILE" ]]; then
    echo "    прошлых релизов нет: $LAST_RELEASE_FILE не найден, сверять номер не с чем"
    exit 0
fi

PREVIOUS="$(tr -dc '0-9' < "$LAST_RELEASE_FILE")"

if [[ -z "$PREVIOUS" ]]; then
    echo "ОШИБКА: в $LAST_RELEASE_FILE нет номера прошлого релиза." >&2
    echo "Впишите номер последнего выпущенного релиза или удалите файл." >&2
    exit 1
fi

if [[ "$BUILD" -le "$PREVIOUS" ]]; then
    echo "ОШИБКА: номер сборки $BUILD не больше номера прошлого релиза $PREVIOUS." >&2
    echo "Номер берётся из времени по UTC — проверьте часы на машине." >&2
    exit 1
fi

echo "    номер сборки $BUILD больше прошлого релиза $PREVIOUS"
