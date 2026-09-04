#!/bin/bash
# Собирает Clepsydra.app из SwiftPM-пакета. Полный Xcode не нужен —
# хватает Command Line Tools.
#
#   ./build.sh              ad-hoc подпись, только для своей машины
#   ./build.sh --release    Developer ID + нотаризация, для раздачи другим
#
# Для релиза нужны переменные:
#   DEV_ID          имя сертификата, напр. "Developer ID Application: Ivan Ivanov (AB12CD34EF)"
#                   если не задана — берётся первый подходящий из связки ключей
#   NOTARY_PROFILE  имя профиля notarytool (по умолчанию clepsydra)
set -euo pipefail

cd "$(dirname "$0")"

APP="Clepsydra.app"
CONFIG=release
RELEASE=false
[[ "${1:-}" == "--release" ]] && RELEASE=true

# Номер сборки — время по UTC, см. docs/development.md.
BUILD="$(./Tools/build-number.sh)"
LAST_RELEASE_FILE=last-release-build

# Ворота релиза: выпуск с невыросшим номером обновление никому не покажет.
# Сверяем до сборки, а не после нотаризации.
if [[ "$RELEASE" == true ]]; then
    if [[ ! -f "$LAST_RELEASE_FILE" ]]; then
        echo "==> прошлых релизов нет: $LAST_RELEASE_FILE не найден, сверять номер не с чем"
    else
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
    fi
fi

echo "==> прогон тестов"
swift run -c "$CONFIG" --arch arm64 ClepsydraTests

echo "==> swift build ($CONFIG, arm64)"
swift build -c "$CONFIG" --arch arm64 --product Clepsydra

BIN="$(swift build -c "$CONFIG" --arch arm64 --show-bin-path)/Clepsydra"

echo "==> сборка бандла $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Clepsydra"
cp Resources/Info.plist "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD" "$APP/Contents/Info.plist"
echo "    номер сборки: $BUILD"

# Фотографии для режима Стетхема — если положены. Их нет в репозитории:
# это снимки реального человека, права на них не наши.
if [[ -d Resources/statham ]]; then
    cp -R Resources/statham "$APP/Contents/Resources/statham"
    echo "    фотографий для режима Стетхема: $(ls Resources/statham | wc -l | tr -d ' ')"
else
    echo "    Resources/statham нет — режим Стетхема покажет наклейки без фигуры"
fi

# Портреты философов — по имени автора латиницей, см. Quotes.portraits.
if [[ -d Resources/philosophers ]]; then
    cp -R Resources/philosophers "$APP/Contents/Resources/philosophers"
    echo "    портретов философов: $(ls Resources/philosophers | wc -l | tr -d ' ')"
else
    echo "    Resources/philosophers нет — философский режим покажет цитату без портрета"
fi
printf 'APPL????' > "$APP/Contents/PkgInfo"
cp Resources/Clepsydra.icns "$APP/Contents/Resources/Clepsydra.icns"

if [[ "$RELEASE" == false ]]; then
    echo "==> ad-hoc подпись"
    codesign --force --sign - --options runtime "$APP"
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
# --timestamp обязателен для нотаризации, --options runtime включает hardened runtime
codesign --force --timestamp --options runtime --sign "$IDENTITY" "$APP"
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

echo "$BUILD" > "$LAST_RELEASE_FILE"

echo "==> готово: $(pwd)/$DIST — можно раздавать"
echo "    номер релиза $BUILD записан в $LAST_RELEASE_FILE — закоммитьте файл"
lipo -archs "$APP/Contents/MacOS/Clepsydra"
