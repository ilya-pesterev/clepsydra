// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Clepsydra",
    platforms: [.macOS(.v14)],
    targets: [
        // Автомат состояний и цитаты — без AppKit, поэтому покрыты тестами.
        .target(
            name: "ClepsydraCore",
            path: "Sources/ClepsydraCore",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "Clepsydra",
            dependencies: ["ClepsydraCore"],
            path: "Sources/Clepsydra",
            swiftSettings: [.swiftLanguageMode(.v5)]
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
