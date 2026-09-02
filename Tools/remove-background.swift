#!/usr/bin/env swift
//
// Снимает фон с фотографий для режима Стетхема.
//
//   swift Tools/remove-background.swift Resources/statham/*.png
//
// Работает через Vision — тот же механизм, что у «Удалить фон» в Просмотре.
// Принимает любой формат, который читает система, и всегда пишет рядом PNG:
// без альфа-канала белый кант считать не из чего. Исходник другого формата
// после этого удаляется, поэтому оригиналы стоит отложить в сторону.

import AppKit
import Vision
import CoreImage

let files = CommandLine.arguments.dropFirst().map { URL(fileURLWithPath: $0) }

guard !files.isEmpty else {
    print("Укажите файлы: swift Tools/remove-background.swift Resources/statham/*.png")
    exit(1)
}

let context = CIContext()
var failures = 0

for url in files {
    let name = url.lastPathComponent

    guard let source = CIImage(contentsOf: url) else {
        print("✗ \(name): не читается")
        failures += 1
        continue
    }

    let handler = VNImageRequestHandler(ciImage: source)
    let request = VNGenerateForegroundInstanceMaskRequest()

    do {
        try handler.perform([request])
    } catch {
        print("✗ \(name): Vision не справился — \(error.localizedDescription)")
        failures += 1
        continue
    }

    guard let result = request.results?.first, !result.allInstances.isEmpty else {
        print("✗ \(name): фигура не найдена")
        failures += 1
        continue
    }

    do {
        // croppedToInstancesExtent обрезает по контуру: пустые поля вокруг
        // фигуры нам только мешают — наклейка клеится по краю силуэта.
        let masked = try result.generateMaskedImage(
            ofInstances: result.allInstances,
            from: handler,
            croppedToInstancesExtent: true
        )
        let cut = CIImage(cvPixelBuffer: masked)
        guard let png = context.pngRepresentation(
            of: cut, format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB()
        ) else {
            print("✗ \(name): не удалось собрать PNG")
            failures += 1
            continue
        }
        let target = url.deletingPathExtension().appendingPathExtension("png")
        try png.write(to: target)
        if target != url {
            try? FileManager.default.removeItem(at: url)
        }
        let size = cut.extent
        print("✓ \(name) → \(target.lastPathComponent): фигур \(result.allInstances.count), "
              + "обрезано до \(Int(size.width))×\(Int(size.height))")
    } catch {
        print("✗ \(name): \(error.localizedDescription)")
        failures += 1
    }
}

exit(failures == 0 ? 0 : 1)
