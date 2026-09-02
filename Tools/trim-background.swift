#!/usr/bin/env swift
//
// Убирает ровный фон вокруг предмета и обрезает по содержимому.
//
//   swift Tools/trim-background.swift вход.jpg выход.png
//
// Для рендеров на однотонной подложке это точнее, чем Vision: заливка от краёв
// не трогает блики внутри предмета, а полупрозрачным пикселям кромки возвращает
// их собственный цвет — иначе по краю остаётся серая бахрома.

import AppKit

let arguments = CommandLine.arguments.dropFirst()
guard arguments.count == 2 else {
    print("Нужны два пути: вход и выход")
    exit(1)
}
let input = URL(fileURLWithPath: arguments.first!)
let output = URL(fileURLWithPath: arguments.dropFirst().first!)

guard let source = NSImage(contentsOf: input),
      let cg = source.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    print("Не читается: \(input.lastPathComponent)")
    exit(1)
}

let width = cg.width, height = cg.height
var pixels = [UInt8](repeating: 0, count: width * height * 4)
guard let context = CGContext(
    data: &pixels, width: width, height: height, bitsPerComponent: 8,
    bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else { exit(1) }
context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))

@inline(__always) func index(_ x: Int, _ y: Int) -> Int { (y * width + x) * 4 }

/// Фон берём из углов: медиана устойчивее среднего к случайной пылинке.
func backgroundColour() -> (Double, Double, Double) {
    var samples: [(Double, Double, Double)] = []
    for (cx, cy) in [(2, 2), (width - 3, 2), (2, height - 3), (width - 3, height - 3)] {
        for dx in 0..<6 {
            for dy in 0..<6 {
                let x = min(max(cx + dx - 3, 0), width - 1)
                let y = min(max(cy + dy - 3, 0), height - 1)
                let i = index(x, y)
                samples.append((Double(pixels[i]), Double(pixels[i + 1]), Double(pixels[i + 2])))
            }
        }
    }
    let r = samples.map(\.0).sorted()[samples.count / 2]
    let g = samples.map(\.1).sorted()[samples.count / 2]
    let b = samples.map(\.2).sorted()[samples.count / 2]
    return (r, g, b)
}

let background = backgroundColour()

@inline(__always) func distance(_ i: Int) -> Double {
    let dr = Double(pixels[i])     - background.0
    let dg = Double(pixels[i + 1]) - background.1
    let db = Double(pixels[i + 2]) - background.2
    return (dr * dr + dg * dg + db * db).squareRoot()
}

// Заливка от краёв: фоном считаем только то, что связано с рамкой кадра.
// Так одинаковый по цвету участок внутри предмета не выест дырку.
let flatTolerance = 18.0
var isBackground = [Bool](repeating: false, count: width * height)
var queue: [Int] = []
queue.reserveCapacity(width * height / 4)

for x in 0..<width {
    for y in [0, height - 1] where !isBackground[y * width + x] && distance(index(x, y)) <= flatTolerance {
        isBackground[y * width + x] = true
        queue.append(y * width + x)
    }
}
for y in 0..<height {
    for x in [0, width - 1] where !isBackground[y * width + x] && distance(index(x, y)) <= flatTolerance {
        isBackground[y * width + x] = true
        queue.append(y * width + x)
    }
}

var head = 0
while head < queue.count {
    let cell = queue[head]; head += 1
    let x = cell % width, y = cell / width
    for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
        let nx = x + dx, ny = y + dy
        guard nx >= 0, nx < width, ny >= 0, ny < height else { continue }
        let next = ny * width + nx
        guard !isBackground[next], distance(index(nx, ny)) <= flatTolerance else { continue }
        isBackground[next] = true
        queue.append(next)
    }
}

// Кромка: сколько шагов до фона. Дальше третьего шага пиксель считаем плотным.
let feather = 3
var depth = [Int](repeating: Int.max, count: width * height)
var edge: [Int] = []
for cell in 0..<(width * height) where isBackground[cell] { depth[cell] = 0; edge.append(cell) }
head = 0
while head < edge.count {
    let cell = edge[head]; head += 1
    let step = depth[cell]
    guard step < feather else { continue }
    let x = cell % width, y = cell / width
    for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
        let nx = x + dx, ny = y + dy
        guard nx >= 0, nx < width, ny >= 0, ny < height else { continue }
        let next = ny * width + nx
        guard depth[next] > step + 1 else { continue }
        depth[next] = step + 1
        edge.append(next)
    }
}

// Матирование: полупрозрачным пикселям возвращаем их собственный цвет,
// вычитая подмешанный фон. Без этого по краю остаётся серая бахрома.
let softness = 70.0
var minX = width, minY = height, maxX = -1, maxY = -1

for y in 0..<height {
    for x in 0..<width {
        let cell = y * width + x
        let i = index(x, y)
        var alpha = 1.0

        if isBackground[cell] {
            alpha = 0
        } else if depth[cell] <= feather {
            alpha = min(1, distance(i) / softness)
        }

        if alpha <= 0.004 {
            pixels[i] = 0; pixels[i + 1] = 0; pixels[i + 2] = 0; pixels[i + 3] = 0
            continue
        }

        if alpha < 1 {
            for channel in 0..<3 {
                let observed = Double(pixels[i + channel])
                let base = channel == 0 ? background.0 : (channel == 1 ? background.1 : background.2)
                let own = (observed - (1 - alpha) * base) / alpha
                pixels[i + channel] = UInt8(min(255, max(0, own.rounded())))
            }
        }

        // Буфер премультиплицированный — цвет умножаем на альфу сами.
        for channel in 0..<3 {
            pixels[i + channel] = UInt8((Double(pixels[i + channel]) * alpha).rounded())
        }
        pixels[i + 3] = UInt8((alpha * 255).rounded())

        minX = min(minX, x); maxX = max(maxX, x)
        minY = min(minY, y); maxY = max(maxY, y)
    }
}

guard maxX >= minX, maxY >= minY else {
    print("Ничего не осталось — фон съел всё. Проверь допуск.")
    exit(1)
}

guard let trimmed = context.makeImage()?.cropping(
    to: CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
) else { exit(1) }

let rep = NSBitmapImageRep(cgImage: trimmed)
guard let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
try png.write(to: output)

print("✓ \(input.lastPathComponent) → \(output.lastPathComponent): "
      + "\(trimmed.width)×\(trimmed.height), фон \(Int(background.0)),\(Int(background.1)),\(Int(background.2))")
