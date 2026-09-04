#!/bin/bash
# Собирает Clepsydra.app из SwiftPM-пакета. Полный Xcode не нужен —
# хватает Command Line Tools.
#
#   ./build.sh              ad-hoc подпись, только для своей машины
#   ./build.sh --dmg        плюс Clepsydra-<версия>.dmg рядом с бандлом
#   ./build.sh --release    Developer ID + нотаризация, для раздачи другим
#
# Флаги складываются: --release --dmg выпускает нотаризованный DMG.
# Обычная сборка DMG не делает — монтировать том и ждать Finder на каждой
# сборке для разработки незачем.
#
# Для релиза нужны переменные:
#   DEV_ID          имя сертификата, напр. "Developer ID Application: Ivan Ivanov (AB12CD34EF)"
#                   если не задана — берётся первый подходящий из связки ключей
#   NOTARY_PROFILE  имя профиля notarytool (по умолчанию clepsydra)
set -euo pipefail

cd "$(dirname "$0")"

APP="Clepsydra.app"
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework"
# Версия фреймворка у Sparkle называется буквой B — так и лежит внутри
# XCFramework. Имя в одном месте: сменись оно, сборка отвалится на подписи,
# а не выпустит молча бандл без половины содержимого.
SPARKLE_VERSION="$SPARKLE/Versions/B"
CONFIG=release
RELEASE=false
DMG=false

for argument in "$@"; do
    case "$argument" in
        --release) RELEASE=true ;;
        --dmg)     DMG=true ;;
        *)
            echo "ОШИБКА: неизвестный ключ $argument (есть --release и --dmg)." >&2
            exit 1
            ;;
    esac
done

# Подписывает бандл целиком, изнутри наружу. Порядок не вкусовщина: подпись
# внешнего бандла запечатывает то, что уже подписано внутри, и фреймворк,
# подписанный последним, сломал бы подпись приложения.
#
#   sign_bundle -                                        ad-hoc
#   sign_bundle "$IDENTITY" --timestamp --options runtime
sign_bundle() {
    local identity="$1"
    shift
    codesign --force --sign "$identity" "$@" \
        "$SPARKLE_VERSION/Updater.app" \
        "$SPARKLE_VERSION/Autoupdate" \
        "$SPARKLE" \
        "$APP"
}

# Номер сборки — время по UTC, см. docs/development.md.
BUILD="$(./Tools/build-number.sh)"
LAST_RELEASE_FILE=last-release-build

# Ворота релиза: выпуск с невыросшим номером обновление никому не покажет.
# Сверяем до сборки, а не после нотаризации. Те же ворота стоят в release.sh.
if [[ "$RELEASE" == true ]]; then
    echo "==> ворота релиза"
    ./Tools/release-gate.sh "$BUILD" "$LAST_RELEASE_FILE"
fi

echo "==> прогон тестов"
swift run -c "$CONFIG" --arch arm64 ClepsydraTests

echo "==> swift build ($CONFIG, arm64)"
swift build -c "$CONFIG" --arch arm64 --product Clepsydra

BIN_PATH="$(swift build -c "$CONFIG" --arch arm64 --show-bin-path)"
BIN="$BIN_PATH/Clepsydra"

echo "==> сборка бандла $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$BIN" "$APP/Contents/MacOS/Clepsydra"

# Фреймворк установщика едет внутри бандла: обновление ставится на месте, и
# ищет его исполняемый файл рядом с собой (@executable_path/../Frameworks,
# см. Package.swift). Без него приложение не запустится вовсе.
#
# ditto, а не cp: внутри фреймворка символические ссылки (Versions/Current),
# и подпись после копирования обычным cp не сходится.
ditto "$BIN_PATH/Sparkle.framework" "$SPARKLE"

# XPC-службы Sparkle нужны приложению в песочнице — оно ходит в сеть и ставит
# обновление через них. Clepsydra не в песочнице, делает то и другое сама, и
# лишние исполняемые файлы в бандле только увеличивают то, что приходится
# подписывать и за что отвечать.
#
# Заголовки и модули нужны тому, кто собирается с фреймворком, а не тому, кто
# его запускает: в бандл они едут мёртвым грузом.
#
# Ссылка с верхнего уровня фреймворка убирается вместе с папкой: оставленная
# в одиночестве, она указывает в пустоту — и уезжает такой людям.
for unused in XPCServices Headers PrivateHeaders Modules; do
    rm -rf "$SPARKLE_VERSION/$unused" "$SPARKLE/$unused"
done

cp Resources/Info.plist "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD" "$APP/Contents/Info.plist"
echo "    номер сборки: $BUILD"

# Фотографии для режима Стетхема — если положены. Их нет в репозитории:
# это снимки реального человека, права на них не наши.
if [[ -d Resources/statham ]]; then
    cp -R Resources/statham "$APP/Contents/Resources/statham"
fi

# Портреты философов — по имени автора латиницей, см. Quotes.portraits.
if [[ -d Resources/philosophers ]]; then
    cp -R Resources/philosophers "$APP/Contents/Resources/philosophers"
fi

# Считает и называет их тот же скрипт, что и перед релизом. Код 2 — часть
# картинок не доехала: для сборки это не отказ, для ./release.sh — повод
# переспросить.
./Tools/bundle-pictures.sh "$APP" || true
printf 'APPL????' > "$APP/Contents/PkgInfo"
cp Resources/Clepsydra.icns "$APP/Contents/Resources/Clepsydra.icns"

if [[ "$RELEASE" == false ]]; then
    echo "==> ad-hoc подпись"
    # Без --options runtime, и это не забывчивость. Hardened runtime включает
    # library validation: приложение соглашается грузить только те библиотеки,
    # что подписаны тем же Team ID. У ad-hoc подписи Team ID нет вовсе, и
    # собственный Sparkle.framework в бандле после такой подписи не грузится —
    # приложение не запускается вообще. Hardened runtime нужен нотаризации,
    # а её в этой ветке нет.
    sign_bundle -
    codesign --verify --strict "$APP"
    if [[ "$DMG" == true ]]; then ./Tools/make-dmg.sh "$APP"; fi
    echo "==> готово: $(pwd)/$APP"
    echo "    Gatekeeper такую подпись отклонит — для раздачи нужен ./build.sh --release"
    lipo -archs "$APP/Contents/MacOS/Clepsydra"
    exit 0
fi

# --- Релизная ветка -----------------------------------------------------------

IDENTITY="${DEV_ID:-$(security find-identity -v -p codesigning \
    | grep "Developer ID Application" | head -1 | sed 's/.*"\(.*\)".*/\1/')}"

if [[ -z "$IDENTITY" ]]; then
    echo "ОШИБКА: не найден сертификат Developer ID Application." >&2
    echo "Заведите его в аккаунте разработчика и установите в связку ключей," >&2
    echo "либо задайте DEV_ID вручную." >&2
    exit 1
fi

PROFILE="${NOTARY_PROFILE:-clepsydra}"

echo "==> подпись: $IDENTITY"
# --timestamp обязателен для нотаризации, --options runtime включает hardened runtime.
# Здесь он безопасен: и фреймворк, и приложение подписаны одним Developer ID,
# и library validation находит один Team ID у обоих.
sign_bundle "$IDENTITY" --timestamp --options runtime
codesign --verify --strict --verbose=2 "$APP"

echo "==> отправка на нотаризацию (профиль $PROFILE)"
ZIP="Clepsydra-upload.zip"
rm -f "$ZIP"
# ditto, а не zip: сохраняет структуру бандла и права
ditto -c -k --keepParent "$APP" "$ZIP"

if ! xcrun notarytool submit "$ZIP" --keychain-profile "$PROFILE" --wait; then
    echo "Нотаризация не прошла. Подробности:" >&2
    echo "  xcrun notarytool history --keychain-profile $PROFILE" >&2
    echo "  xcrun notarytool log <submission-id> --keychain-profile $PROFILE" >&2
    exit 1
fi

echo "==> прикрепление тикета"
# Тикет крепится к бандлу, а не к архиву — архив после этого пересобирается
xcrun stapler staple "$APP"
rm -f "$ZIP"

DIST="Clepsydra.zip"
rm -f "$DIST"
ditto -c -k --keepParent "$APP" "$DIST"

echo "==> проверка Gatekeeper"
spctl -a -vvv "$APP"
xcrun stapler validate "$APP"

if [[ "$DMG" == true ]]; then
    ./Tools/make-dmg.sh "$APP"
    DMG_FILE="$(./Tools/dmg-name.sh)"
    # Сам образ тоже подписывается и нотаризуется: Gatekeeper проверяет
    # скачанный файл, а не только приложение внутри него.
    echo "==> подпись и нотаризация $DMG_FILE"
    codesign --force --timestamp --sign "$IDENTITY" "$DMG_FILE"

    if ! xcrun notarytool submit "$DMG_FILE" --keychain-profile "$PROFILE" --wait; then
        echo "Нотаризация образа не прошла. Подробности:" >&2
        echo "  xcrun notarytool history --keychain-profile $PROFILE" >&2
        echo "  xcrun notarytool log <submission-id> --keychain-profile $PROFILE" >&2
        echo "Бандл к этому моменту уже нотаризован — раздавайте $DIST," >&2
        echo "пока образ не починен." >&2
        exit 1
    fi

    xcrun stapler staple "$DMG_FILE"
    spctl -a -t open --context context:primary-signature -vvv "$DMG_FILE"
fi

echo "$BUILD" > "$LAST_RELEASE_FILE"

echo "==> готово: $(pwd)/$DIST — можно раздавать"
if [[ "$DMG" == true ]]; then
    echo "            $(pwd)/$DMG_FILE — то же самое для тех, кто не знает про zip"
fi
echo "    номер релиза $BUILD записан в $LAST_RELEASE_FILE — закоммитьте файл"
lipo -archs "$APP/Contents/MacOS/Clepsydra"
