import Foundation

/// Крошечная замена XCTest. Полного Xcode на машине нет, а вместе с ним нет ни
/// XCTest, ни swift-testing — обе библиотеки лежат внутри Xcode, а не в Command
/// Line Tools. Тянуть swift-testing отдельным пакетом ради двух десятков
/// проверок дороже, чем написать их здесь.
final class Runner {

    private struct Failure {
        let test: String
        let detail: String
        let line: Int
    }

    private var failures: [Failure] = []
    private var current = "—"
    private var passed = 0

    func test(_ name: String, _ body: () -> Void) {
        current = name
        let before = failures.count
        body()
        if failures.count == before { passed += 1 }
    }

    func expect<T: Equatable>(_ actual: T, _ expected: T, _ note: String = "", line: Int = #line) {
        guard actual != expected else { return }
        let suffix = note.isEmpty ? "" : " — \(note)"
        failures.append(Failure(
            test: current,
            detail: "ожидалось \(expected), получено \(actual)\(suffix)",
            line: line
        ))
    }

    /// Печатает итог и завершает процесс: ненулевой код — чтобы сборка падала.
    func finish() -> Never {
        for failure in failures {
            FileHandle.standardError.write(
                "✗ \(failure.test)\n  строка \(failure.line): \(failure.detail)\n".data(using: .utf8)!
            )
        }
        if failures.isEmpty {
            print("✓ \(passed) проверок пройдено")
            exit(0)
        }
        FileHandle.standardError.write(
            "\n\(failures.count) провалено, \(passed) пройдено\n".data(using: .utf8)!
        )
        exit(1)
    }
}
