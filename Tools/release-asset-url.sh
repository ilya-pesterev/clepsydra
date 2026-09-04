#!/bin/bash
# Печатает адрес файла, приложенного к релизу.
#
#   ./Tools/release-asset-url.sh 1.1 Clepsydra.zip
#
# Адрес ведёт на файл того самого выпуска, а не на releases/latest: и фид, и
# фид установщика описывают конкретную версию, а «последний» за время между
# чтением фида и скачиванием успеет смениться.
#
# Собирается в одном месте на оба фида. Разойдись они, фид обещал бы одно, а
# ставилось бы другое — и заметил бы это не автор, а тот, у кого обновление
# однажды не встало.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-}"
FILE="${2:-}"

# Букву v пишут и не пишут — как в Tools/release-tag.sh, где живёт сам тег.
VERSION="${VERSION#v}"

if [[ -z "$VERSION" ]]; then
    echo "ОШИБКА: не названа версия выпуска." >&2
    exit 1
fi

if [[ -z "$FILE" ]]; then
    echo "ОШИБКА: не назван файл, к которому нужен адрес." >&2
    exit 1
fi

REPOSITORY="$(./Tools/origin-repo.sh)"

echo "https://github.com/$REPOSITORY/releases/download/v$VERSION/$FILE"
