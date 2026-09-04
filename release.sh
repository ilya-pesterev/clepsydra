#!/bin/bash
# Выпускает релиз Clepsydra: собирает DMG, ставит тег и создаёт черновик
# релиза на GitHub — одной командой с машины автора.
#
#   ./release.sh 1.0        собрать, отметить тегом, положить черновиком
#
# Черновик — не оговорка: пока релиз в черновике, файл можно скачать и пройти
# весь путь установки. Открыть его людям — отдельный шаг, команда напечатана
# в конце. Порядок выпуска целиком — в docs/development.md.
#
# Релиз уходит в origin: код живёт там, а задачи — в другом репозитории.
set -euo pipefail
cd "$(dirname "$0")"

APP="Clepsydra.app"
LAST_RELEASE_FILE=last-release-build
CHANGES_DIRECTORY=docs/releases

# Релизы уходят туда, где живёт код. Задачи заведены в другом репозитории,
# и перепутанный origin отправил бы черновик с образом молча не туда.
EXPECTED_REPOSITORY=ilya-pesterev/clepsydra

ASKED_VERSION=""

REPOSITORY=""   # owner/name, куда уходит релиз
TAG=""          # v1.0
VERSION=""      # 1.0
BUILD=""        # номер сборки из готового бандла
CHANGES=""      # docs/releases/1.0.md
NOTES=""        # собранное описание релиза, файл
PUBLISHED=""    # копия образа под именем, под которым он уходит в релиз
UPLOAD=()       # что прикладывается к релизу

step() { echo "==> $1"; }

fail() { echo "ОШИБКА: $1" >&2; exit 1; }

# Описание и копия образа под релизным именем нужны только на время выпуска —
# и убираются, чем бы он ни кончился. Рядом остаётся собранный Clepsydra-<версия>.dmg.
remove_leftovers() {
    if [[ -n "$NOTES" ]]; then rm -f "$NOTES"; fi
    if [[ -n "$PUBLISHED" ]]; then rm -f "$PUBLISHED" "$PUBLISHED.sha256"; fi
}
trap remove_leftovers EXIT

# Спрашивает, продолжать ли. Отказ — не ошибка сборки, но и не публикация.
confirm() {
    if [[ ! -t 0 ]]; then
        fail "спросить подтверждение некому — запуск не с терминала. Релиз собирают руками, с машины автора."
    fi
    local answer
    read -r -p "$1 [да/нет] " answer
    case "$answer" in
        да|Да|д|y|yes) ;;
        *) echo "Отменено — ничего не опубликовано."; exit 1 ;;
    esac
}

# --- Шаги ---------------------------------------------------------------------

parse_arguments() {
    for argument in "$@"; do
        case "$argument" in
            -*) fail "неизвестный ключ $argument — у выпуска ключей нет, только версия." ;;
            *)
                [[ -z "$ASKED_VERSION" ]] \
                    || fail "версию называют один раз, а не «$ASKED_VERSION» и «$argument»."
                ASKED_VERSION="$argument"
                ;;
        esac
    done
}

check_tools() {
    step "чем выпускаем"
    command -v gh >/dev/null || fail "нет gh — поставьте GitHub CLI: brew install gh."
    gh auth status >/dev/null 2>&1 || fail "gh не залогинен: gh auth login."

    REPOSITORY="$(./Tools/origin-repo.sh)"
    if [[ "$REPOSITORY" != "$EXPECTED_REPOSITORY" ]]; then
        fail "origin — $REPOSITORY, а релизы уходят в $EXPECTED_REPOSITORY."
    fi
    echo "    релиз уйдёт в $REPOSITORY"
}

# Версию называет человек, и она сверяется с бандлом до всего остального:
# релиз v1.0 с бандлом версии 0.9 — страница, которая обещает не то.
check_version() {
    step "версия"
    TAG="$(./Tools/release-tag.sh "$ASKED_VERSION")"
    VERSION="${TAG#v}"
    echo "    $TAG"

    if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
        fail "тег $TAG уже есть локально. Уберите его или назовите другую версию."
    fi
    if git ls-remote --exit-code --tags origin "refs/tags/$TAG" >/dev/null 2>&1; then
        fail "тег $TAG уже есть в origin — эта версия выпущена."
    fi
    if gh release view "$TAG" --repo "$REPOSITORY" >/dev/null 2>&1; then
        fail "релиз $TAG в $REPOSITORY уже создан."
    fi
}

# Описание собирается до сборки: файл со списком изменений забывают чаще, чем
# что-либо ещё, и узнавать об этом через десять минут сборки незачем.
check_notes() {
    step "описание релиза"
    CHANGES="$CHANGES_DIRECTORY/$VERSION.md"
    NOTES="$(mktemp -t clepsydra-release-notes)"
    ./Tools/release-notes.sh "$CHANGES" > "$NOTES"
    echo "    что изменилось — из $CHANGES"
}

check_tree() {
    step "рабочее дерево"
    if [[ -n "$(git status --porcelain)" ]]; then
        git status --short >&2
        fail "в рабочем дереве есть незакоммиченные изменения — тег указал бы не на то, что выпускается."
    fi

    local branch ahead
    branch="$(git rev-parse --abbrev-ref HEAD)"
    git fetch --quiet origin
    git rev-parse -q --verify "refs/remotes/origin/$branch" >/dev/null \
        || fail "ветки $branch нет в origin: git push -u origin $branch."
    ahead="$(git rev-list --count "origin/$branch..HEAD")"
    if [[ "$ahead" != 0 ]]; then
        fail "$ahead коммитов не отправлено в origin — тег указал бы на коммит, которого там нет: git push origin $branch."
    fi
    echo "    $branch чист и отправлен"
}

# Сверяем до сборки, как build.sh: сбитые часы не должны отваливать выпуск
# через десять минут после тестов. Номер к концу сборки только вырастет,
# так что прошедшая проверка останется верной.
check_build_number() {
    step "ворота релиза"
    local now
    now="$(./Tools/build-number.sh)"
    ./Tools/release-gate.sh "$now" "$LAST_RELEASE_FILE"
}

# Тесты прогоняет build.sh — до сборки бандла, до всего остального.
build() {
    step "сборка"
    ./build.sh --dmg

    # Номер релиза берётся из готового бандла, а не из времени: в
    # last-release-build должно лечь то, что уехало людям.
    BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist")"
}

# Портретов и фотографий в репозитории нет — права на них не наши, и сборка
# берёт их с машины автора. Молча выпустить сборку, где экран покажет цитату
# без портрета, нельзя: считает и называет их Tools/bundle-pictures.sh, тот же,
# что печатает счёт в сборке, а код возврата 2 — это и есть повод переспросить.
report_bundle_contents() {
    step "что уехало в бандл"
    if ./Tools/bundle-pictures.sh "$APP"; then return; fi
    echo
    confirm "Выпускать релиз с такой сборкой?"
}

# Артефактов в релизе будет больше одного: к DMG для первой установки встанет
# архив для обновления. Поэтому список, а не переменная, — сумма посчитается
# новому файлу тем же циклом.
#
# Образ уходит под именем без версии: первый пункт «Установки» в README ведёт
# на releases/latest/download/<имя>, и переименование образа от релиза к релизу
# ломало бы эту ссылку каждый раз. Собранный файл имя с версией сохраняет —
# копия под релизным именем живёт только до конца выпуска.
collect_artifacts() {
    step "контрольные суммы"
    local built
    built="$(./Tools/dmg-name.sh)"
    [[ -f "$built" ]] || fail "нет файла $built — сборка не положила то, что обещала."
    PUBLISHED="$(./Tools/dmg-name.sh --published)"
    rm -f "$PUBLISHED"
    cp "$built" "$PUBLISHED"
    echo "    $built уходит в релиз как $PUBLISHED"
    local artifacts=("$PUBLISHED")
    local file
    UPLOAD=()
    for file in "${artifacts[@]}"; do
        [[ -f "$file" ]] || fail "нет файла $file — сборка не положила то, что обещала."
        shasum -a 256 "$file" > "$file.sha256"
        echo "    $(cat "$file.sha256")"
        UPLOAD+=("$file" "$file.sha256")
    done
}

create_tag() {
    step "тег $TAG"
    git tag -a "$TAG" -m "Clepsydra $VERSION"
    git push --quiet origin "$TAG"
}

publish_draft() {
    step "черновик релиза в $REPOSITORY"
    # Развернуть пустой массив под set -u в bash 3.2 — «unbound variable»,
    # а не внятный отказ. Проверяем длиной, она пустого массива не боится.
    [[ ${#UPLOAD[@]} -gt 0 ]] || fail "к релизу нечего приложить."
    if ! gh release create "$TAG" \
            --repo "$REPOSITORY" \
            --draft \
            --title "Clepsydra $VERSION" \
            --notes-file "$NOTES" \
            "${UPLOAD[@]}"; then
        echo "Релиз не создан, а тег $TAG уже в origin. Убрать его:" >&2
        echo "  git tag -d $TAG && git push origin :refs/tags/$TAG" >&2
        exit 1
    fi
}

record_build_number() {
    echo "$BUILD" > "$LAST_RELEASE_FILE"
    step "готово: черновик $TAG собран и лежит в $REPOSITORY"
    echo "    скачайте DMG со страницы черновика и пройдите установку целиком"
    echo "    открыть людям: gh release edit $TAG --repo $REPOSITORY --draft=false"
    echo "    номер релиза $BUILD записан в $LAST_RELEASE_FILE — закоммитьте файл"
}

# --- Порядок выпуска ----------------------------------------------------------
# Всё, что может отказать, стоит до create_tag: до него ничего не опубликовано.

parse_arguments "$@"
check_tools
check_version
check_notes
check_tree
check_build_number
build
report_bundle_contents
collect_artifacts
create_tag
publish_draft
record_build_number
