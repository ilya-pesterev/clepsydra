#!/bin/bash
# Собирает DMG с перетаскиванием в Applications из готового Clepsydra.app.
#
#   ./Tools/make-dmg.sh              берёт ./Clepsydra.app
#   ./Tools/make-dmg.sh путь/до.app  берёт указанный бандл
#
# Имя файла — из Tools/dmg-name.sh, версия в нём приходит из Info.plist.
# Оформление окна ставит Finder по AppleScript, см. docs/adr/0008-dmg-window-is-dressed-by-finder.md:
# при первом прогоне macOS спросит разрешение на автоматизацию Finder.
set -euo pipefail
cd "$(dirname "$0")/.."

APP="${1:-Clepsydra.app}"
VOLUME=Clepsydra
DMG="$(./Tools/dmg-name.sh)"

# Раскладка окна. Отсюда её берут и AppleScript, и рисовальщик фона —
# числа живут в одном месте, чтобы стрелка не разошлась с иконками.
WINDOW_WIDTH=660
WINDOW_HEIGHT=400
ICON_SIZE=128
ICON_ROW=160
APP_COLUMN=170
APPLICATIONS_COLUMN=490

if [[ ! -d "$APP" ]]; then
    echo "ОШИБКА: нет бандла $APP — соберите его через ./build.sh." >&2
    exit 1
fi

STAGE="$(mktemp -d)"
WRITABLE="$(mktemp -d)/rw.dmg"
DEVICE=""

# Смонтированный том после падения — это и следующая сборка сломает, и
# «Clepsydra 1» в Finder. Отцепляем в любом случае, даже по Ctrl-C.
cleanup() {
    if [[ -n "$DEVICE" ]]; then
        hdiutil detach "$DEVICE" -quiet 2>/dev/null \
            || hdiutil detach "$DEVICE" -force -quiet 2>/dev/null \
            || true
    fi
    rm -rf "$STAGE" "$(dirname "$WRITABLE")"
}
trap cleanup EXIT

# Том с таким же именем уже висит — иначе Finder смонтирует «Clepsydra 1»,
# и оформление уедет не на тот том.
if [[ -d "/Volumes/$VOLUME" ]]; then
    echo "==> отцепляю оставшийся том /Volumes/$VOLUME"
    hdiutil detach "/Volumes/$VOLUME" -quiet 2>/dev/null \
        || hdiutil detach "/Volumes/$VOLUME" -force -quiet
fi

echo "==> начинка тома"
# ditto, а не cp: сохраняет права и расширенные атрибуты, а вместе с ними
# подпись бандла — сломанная подпись даёт «повреждено и не может быть открыто».
ditto "$APP" "$STAGE/$(basename "$APP")"
ln -s /Applications "$STAGE/Applications"

mkdir -p "$STAGE/.background"
swift Tools/make-dmg-background.swift "$STAGE/.background" \
    "$WINDOW_WIDTH" "$WINDOW_HEIGHT" "$ICON_SIZE" "$ICON_ROW" "$APP_COLUMN" "$APPLICATIONS_COLUMN" >/dev/null
# Одна картинка на оба разрешения: Finder берёт из TIFF нужную сам.
tiffutil -cathidpicheck "$STAGE/.background/background.png" "$STAGE/.background/background@2x.png" \
    -out "$STAGE/.background/background.tiff" >/dev/null 2>&1
rm "$STAGE/.background/background.png" "$STAGE/.background/background@2x.png"

echo "==> образ для записи"
SIZE=$(( $(du -sm "$STAGE" | cut -f1) + 30 ))
hdiutil create -srcfolder "$STAGE" -volname "$VOLUME" -fs HFS+ \
    -format UDRW -ov -size "${SIZE}m" "$WRITABLE" >/dev/null

ATTACHED="$(hdiutil attach "$WRITABLE" -readwrite -noverify -noautoopen)"
DEVICE="$(printf '%s\n' "$ATTACHED" | awk '/^\/dev\// { print $1; exit }')"

if [[ -z "$DEVICE" ]]; then
    echo "ОШИБКА: hdiutil не сказал, куда смонтировал образ." >&2
    exit 1
fi

if [[ ! -d "/Volumes/$VOLUME" ]]; then
    echo "ОШИБКА: том смонтировался не как /Volumes/$VOLUME." >&2
    exit 1
fi

# Папка с фоном начинается с точки, но точка прячет только от настроек по
# умолчанию: флаг hidden убирает её и у тех, кто включил показ скрытого.
chflags hidden "/Volumes/$VOLUME/.background"

echo "==> оформление окна"
osascript <<APPLESCRIPT
tell application "Finder"
    tell disk "$VOLUME"
        open
        delay 1
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        -- Боковую панель убирает уже скрытый тулбар: окно без него боковой
        -- панели не имеет вовсе. Ширина в ноль — на случай, если однажды
        -- перестанет. Оба флага уезжают в .DS_Store и едут вместе с образом.
        set sidebar width of container window to 0
        set the bounds of container window to {200, 120, $((200 + WINDOW_WIDTH)), $((120 + WINDOW_HEIGHT))}
        set viewOptions to the icon view options of container window
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to $ICON_SIZE
        set text size of viewOptions to 13
        set label position of viewOptions to bottom
        set background picture of viewOptions to file ".background:background.tiff"
        set position of item "$(basename "$APP")" of container window to {$APP_COLUMN, $ICON_ROW}
        set position of item "Applications" of container window to {$APPLICATIONS_COLUMN, $ICON_ROW}
        update without registering applications
        delay 1
        close
        open
        delay 1
        -- Finder переоткрывает окно в своих размерах и на закрытии записал бы
        -- их поверх наших. Границы ставим ещё раз, последним словом.
        set the bounds of container window to {200, 120, $((200 + WINDOW_WIDTH)), $((120 + WINDOW_HEIGHT))}
        update without registering applications
        delay 2
        close
    end tell
end tell
APPLESCRIPT

# Журнал событий файловой системы человеку не нужен, а в образе только для
# чтения он всё равно мёртвый груз. Флага hidden на нём нет, и у того, кто
# включил показ скрытого, папка была бы видна в окне.
rm -rf "/Volumes/$VOLUME/.fseventsd" "/Volumes/$VOLUME/.Trashes" 2>/dev/null || true

# Finder пишет .DS_Store лениво; без sync оформление уедет мимо образа.
sync

echo "==> сжатие"
hdiutil detach "$DEVICE" -quiet || hdiutil detach "$DEVICE" -force -quiet
DEVICE=""

rm -f "$DMG"
# UDZO — только для чтения и сжатый: скачанный DMG никто не редактирует.
hdiutil convert "$WRITABLE" -format UDZO -imagekey zlib-level=9 -o "$DMG" >/dev/null

echo "==> готово: $(pwd)/$DMG ($(du -h "$DMG" | cut -f1))"
