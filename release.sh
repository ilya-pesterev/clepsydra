#!/bin/bash
# Выпускает релиз Clepsydra: собирает DMG, ставит тег и создаёт черновик
# релиза на GitHub — одной командой с машины автора.
#
#   ./release.sh 1.0        собрать, отметить тегом, положить черновиком
#   ./release.sh 1.0 --yes  не переспрашивать про пустые папки с картинками
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

ASKED=""
CONFIRM=true

REPOSITORY=""   # owner/name, куда уходит релиз
TAG=""          # v1.0
VERSION=""      # 1.0
BUILD=""        # номер сборки из готового бандла
CHANGES=""      # docs/releases/1.0.md
NOTES=""        # собранное описание релиза, файл
UPLOAD=()       # что прикладывается к релизу

step() { echo "==> $1"; }

fail() { echo "ОШИБКА: $1" >&2; exit 1; }

# Спрашивает, продолжать ли. Отказ — не ошибка сборки, но и не публикация.
confirm() {
    if [[ "$CONFIRM" == false ]]; then
        echo "    --yes: подтверждения не спрашиваем"
        return
    fi
    if [[ ! -t 0 ]]; then
        fail "спросить подтверждение некому — запуск не с терминала. Если так и задумано, добавьте --yes."
    fi
    local answer
    read -r -p "$1 [да/нет] " answer
    case "$answer" in
        да|Да|д|y|yes) ;;
        *) echo "Отменено — ничего не опубликовано."; exit 1 ;;
    esac
}

count_files() {
    if [[ ! -d "$1" ]]; then echo 0; return; fi
    find "$1" -type f ! -name '.*' | wc -l | tr -d ' '
}

# --- Шаги ---------------------------------------------------------------------

parse_arguments() {
    for argument in "$@"; do
        case "$argument" in
            --yes) CONFIRM=false ;;
            -*)    fail "неизвестный ключ $argument (есть --yes)." ;;
            *)
                [[ -z "$ASKED" ]] || fail "версию называют один раз, а не «$ASKED» и «$argument»."
                ASKED="$argument"
                ;;
        esac
    done
}

check_tools() {
    step "чем выпускаем"
    command -v gh >/dev/null || fail "нет gh — поставьте GitHub CLI: brew install gh."
    gh auth status >/dev/null 2>&1 || fail "gh не залогинен: gh auth login."

    local url
    url="$(git remote get-url origin 2>/dev/null)" || fail "нет remote origin — публиковать некуда."
    REPOSITORY="$(sed -E 's#^.*github\.com[:/]##; s#\.git$##' <<< "$url")"
    [[ "$REPOSITORY" == */* ]] || fail "origin ($url) не похож на репозиторий GitHub."
    echo "    релиз уйдёт в $REPOSITORY"
}

# Версию называет человек, и она сверяется с бандлом до всего остального:
# релиз v1.0 с бандлом версии 0.9 — страница, которая обещает не то.
check_version() {
    step "версия"
    TAG="$(./Tools/release-tag.sh "$ASKED")"
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

# Тесты прогоняет build.sh — до сборки бандла, до всего остального.
build() {
    step "сборка"
    ./build.sh --dmg

    BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist")"

    step "ворота релиза"
    ./Tools/release-gate.sh "$BUILD" "$LAST_RELEASE_FILE"
}

# Портретов и фотографий в репозитории нет — права на них не наши, и сборка
# берёт их с машины автора. Молча выпустить сборку, где экран покажет цитату
# без портрета, нельзя.
report_bundle_contents() {
    step "что попало в бандл"
    local portraits statham
    portraits="$(count_files "$APP/Contents/Resources/philosophers")"
    statham="$(count_files "$APP/Contents/Resources/statham")"
    echo "    портретов философов: $portraits"
    echo "    фотографий для режима Стетхема: $statham"

    if [[ "$portraits" != 0 && "$statham" != 0 ]]; then return; fi

    echo
    echo "Часть экранов уйдёт в релиз без картинок:"
    if [[ "$portraits" == 0 ]]; then echo "  философский режим покажет цитату без портрета"; fi
    if [[ "$statham" == 0 ]]; then echo "  режим Стетхема покажет наклейки без фигуры"; fi
    confirm "Выпускать такую сборку?"
}

# Артефактов в релизе будет больше одного: к DMG для первой установки встанет
# архив для обновления. Поэтому список, а не переменная, — сумма посчитается
# новому файлу тем же циклом.
collect_artifacts() {
    step "контрольные суммы"
    local artifacts=("$(./Tools/dmg-name.sh)")
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
build
report_bundle_contents
collect_artifacts
create_tag
publish_draft
record_build_number
