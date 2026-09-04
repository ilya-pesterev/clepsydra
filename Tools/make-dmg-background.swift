#!/usr/bin/env swift
//
// Рисует фон окна DMG — стрелку от иконки к папке и подпись «Перетащи в папку».
//
//   swift Tools/make-dmg-background.swift папка ширина высота иконка ряд слева справа
//
// Кладёт в папку background.png (ширина×высота) и background@2x.png вдвое
// крупнее: на retina Finder берёт второй, поэтому картинка не мылит. Дальше
// их склеивает tiffutil, см. Tools/make-dmg.sh.
//
// Рисуем, а не храним готовый PNG: раскладку задаёт Tools/make-dmg.sh — те же
// числа, что уходят в AppleScript, — и картинка не может с ней разойтись.

import AppKit

// Раскладку задаёт Tools/make-dmg.sh — те же числа, что уходят в AppleScript.
// Координаты как у Finder: y растёт вниз от верха окна.
let arguments = Array(CommandLine.arguments.dropFirst())
guard arguments.count == 7,
      let width = Double(arguments[1]),          // ширина окна
      let height = Double(arguments[2]),         // высота окна
      let iconSize = Double(arguments[3]),       // сторона иконки
      let iconRow = Double(arguments[4]),        // центры иконок по вертикали
      let appIcon = Double(arguments[5]),        // центр Clepsydra.app по горизонтали
      let applications = Double(arguments[6])    // центр ярлыка Applications
else {
    print("Нужны семь значений: папка ширина высота размер-иконки ряд-иконок колонка-слева колонка-справа")
    exit(1)
}
let output = URL(fileURLWithPath: arguments[0])

/// Под иконкой Finder рисует её имя, и подпись идёт ниже него: половина иконки
/// вниз до её низа, строка имени, потом воздух.
let iconLabel = 18.0
let captionGap = 64.0
let captionRow = iconRow + iconSize / 2 + iconLabel + captionGap

/// Иконка приложения тёмная — фон светлый, чтобы она читалась силуэтом.
/// Прохладный оттенок взят из воды в иконке.
let top = NSColor(srgbRed: 0.949, green: 0.961, blue: 0.965, alpha: 1)
let bottom = NSColor(srgbRed: 0.878, green: 0.906, blue: 0.918, alpha: 1)
let ink = NSColor(srgbRed: 0.278, green: 0.353, blue: 0.376, alpha: 1)
let accent = NSColor(srgbRed: 0.176, green: 0.443, blue: 0.494, alpha: 1)

func draw(scale: CGFloat, to file: URL) {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(width * scale), pixelsHigh: Int(height * scale),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0
    ) else { exit(1) }
    rep.size = NSSize(width: width, height: height)

    guard let context = NSGraphicsContext(bitmapImageRep: rep) else { exit(1) }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context

    // Все координаты считаем сверху вниз, как в Finder: так числа в скрипте и
    // в AppleScript-е совпадают буквально.
    let flip = NSAffineTransform()
    flip.translateX(by: 0, yBy: height)
    flip.scaleX(by: 1, yBy: -1)
    flip.concat()

    NSGradient(starting: top, ending: bottom)?
        .draw(in: NSRect(x: 0, y: 0, width: width, height: height), angle: 90)

    // Стрелка идёт между иконками, не подходя к ним вплотную.
    drawArrow(from: appIcon + iconSize / 2 + 36, to: applications - iconSize / 2 - 36, at: iconRow)
    drawCaption()

    NSGraphicsContext.restoreGraphicsState()

    guard let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
    do { try png.write(to: file) } catch {
        print("Не записывается: \(file.path)")
        exit(1)
    }
}

/// Стрелка: тонкая линия и открытый наконечник — знак направления, а не
/// нарисованный указатель.
func drawArrow(from start: Double, to end: Double, at y: Double) {
    let head = 13.0
    let line = accent.withAlphaComponent(0.85)

    let shaft = NSBezierPath()
    shaft.move(to: NSPoint(x: start, y: y))
    shaft.line(to: NSPoint(x: end - 2, y: y))
    shaft.lineWidth = 3
    shaft.lineCapStyle = .round
    line.setStroke()
    shaft.stroke()

    let tip = NSBezierPath()
    tip.move(to: NSPoint(x: end - head, y: y - head * 0.8))
    tip.line(to: NSPoint(x: end, y: y))
    tip.line(to: NSPoint(x: end - head, y: y + head * 0.8))
    tip.lineWidth = 3
    tip.lineCapStyle = .round
    tip.lineJoinStyle = .round
    line.setStroke()
    tip.stroke()
}

func drawCaption() {
    let text = "Перетащи в папку"
    let style = NSMutableParagraphStyle()
    style.alignment = .center
    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 16, weight: .medium),
        .foregroundColor: ink,
        .kern: 0.3,
        .paragraphStyle: style
    ]
    let line = NSAttributedString(string: text, attributes: attributes)
    let size = line.size()
    // Текст рисуем в перевёрнутой системе координат, поэтому переворачиваем
    // обратно вокруг его собственной строки — иначе буквы встанут вверх ногами.
    let box = NSRect(x: 0, y: captionRow - size.height / 2, width: width, height: size.height)
    NSGraphicsContext.saveGraphicsState()
    let back = NSAffineTransform()
    back.translateX(by: 0, yBy: box.midY * 2)
    back.scaleX(by: 1, yBy: -1)
    back.concat()
    line.draw(in: box)
    NSGraphicsContext.restoreGraphicsState()
}

draw(scale: 1, to: output.appendingPathComponent("background.png"))
draw(scale: 2, to: output.appendingPathComponent("background@2x.png"))
print("готово: \(output.path)/background.png и background@2x.png")
