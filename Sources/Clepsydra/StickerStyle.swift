import AppKit
import SwiftUI

/// Пара цветов на одну реплику: основной для строк и ударный для последней.
/// Цвет меняется там, где меняется смысл, а не ради пестроты.
struct StickerPalette {

    let base: Color
    let baseInk: Color
    let accent: Color
    let accentInk: Color

    private static let acid   = Color(red: 0.784, green: 0.961, blue: 0.227)
    private static let blue   = Color(red: 0.239, green: 0.545, blue: 0.992)
    private static let pink   = Color(red: 1.000, green: 0.239, blue: 0.604)
    private static let purple = Color(red: 0.545, green: 0.361, blue: 0.965)
    private static let orange = Color(red: 1.000, green: 0.647, blue: 0.122)
    private static let coal   = Color(red: 0.063, green: 0.063, blue: 0.071)

    private static let darkInk  = Color(red: 0.075, green: 0.086, blue: 0.000)

    static let all: [StickerPalette] = [
        StickerPalette(base: blue,   baseInk: .white,  accent: acid,   accentInk: darkInk),
        StickerPalette(base: pink,   baseInk: .white,  accent: acid,   accentInk: darkInk),
        StickerPalette(base: purple, baseInk: .white,  accent: pink,   accentInk: .white),
        StickerPalette(base: coal,   baseInk: .white,  accent: acid,   accentInk: darkInk),
        StickerPalette(base: orange, baseInk: darkInk, accent: purple, accentInk: .white)
    ]

    static func random() -> StickerPalette { all.randomElement() ?? all[0] }
}

/// Фотографии для наклеек. Лежат в бандле рядом с исполняемым файлом; если их
/// нет, режим не ломается — показывает реплику без фигуры.
enum StathamPhotos {

    static let all: [NSImage] = {
        guard let folder = Bundle.main.resourceURL?.appendingPathComponent("statham"),
              let files = try? FileManager.default.contentsOfDirectory(
                  at: folder, includingPropertiesForKeys: nil
              )
        else { return [] }

        return files
            .filter { $0.pathExtension.lowercased() == "png" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap { NSImage(contentsOf: $0) }
    }()

    static func random() -> NSImage? { all.randomElement() }
}
