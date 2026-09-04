// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Clepsydra",
    platforms: [.macOS(.v14)],
    dependencies: [
        // Установщик обновлений. Берётся готовым XCFramework: собирать Sparkle
        // из исходников нечем — на машине одни Command Line Tools.
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.9.6")
    ],
    targets: [
        // Автомат состояний и цитаты — без AppKit, поэтому покрыты тестами.
        .target(
            name: "ClepsydraCore",
            path: "Sources/ClepsydraCore",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "Clepsydra",
            dependencies: ["ClepsydraCore", .product(name: "Sparkle", package: "Sparkle")],
            path: "Sources/Clepsydra",
            swiftSettings: [.swiftLanguageMode(.v5)],
            // Фреймворк едет внутри бандла, рядом с исполняемым файлом:
            // без этого пути загрузчик не найдёт его при запуске.
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        ),
        // Не .testTarget: XCTest и swift-testing поставляются только с полным
        // Xcode, а собираться должно на одних Command Line Tools. Прогон —
        // обычная программа: `swift run ClepsydraTests`.
        .executableTarget(
            name: "ClepsydraTests",
            dependencies: ["ClepsydraCore"],
            path: "Sources/ClepsydraTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
