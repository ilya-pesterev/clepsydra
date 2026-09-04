import Foundation

/// Номер сборки живёт не в Swift, а в `Tools/build-number.sh`, — и проверяется
/// снаружи, ровно так, как его зовёт `build.sh`. Отдельным файлом, чтобы
/// правка сборки не трогала прогон автомата.
func checkBuildNumber(_ t: Runner) {

    // Корень репозитория — от пути этого файла, а не от рабочей папки: прогон
    // запускают и не из корня.
    let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // ClepsydraTests
        .deletingLastPathComponent()   // Sources
        .deletingLastPathComponent()   // корень

    /// Момент приходит снаружи параметром — как и в автомате, иначе проверить
    /// рост нечем. Сорвавшийся запуск отдаёт пустую строку: провал печатает
    /// Runner, а не трап посреди прогона.
    func buildNumber(_ arguments: String...) -> String {
        let process = Process()
        process.executableURL = repoRoot.appendingPathComponent("Tools/build-number.sh")
        process.arguments = arguments
        let out = Pipe()
        process.standardOutput = out
        do { try process.run() } catch { return "" }
        let printed = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: printed, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    t.test("Номер сборки — момент сборки по UTC") {
        t.expect(buildNumber("1700000000"), "20231114221320")
    }

    t.test("Секунда спустя номер больше") {
        // Длина у номеров одна, поэтому строки сравниваются как числа.
        t.expect(buildNumber("1700000001") > buildNumber("1700000000"), true,
                 "сборка идёт дольше секунды, поэтому две подряд не совпадут")
    }

    t.test("Без аргумента берётся текущий момент") {
        let now = buildNumber()
        t.expect(now.count, 14, "YYYYMMDDHHMMSS")
        t.expect(now.allSatisfy(\.isNumber), true, "номера сравнивают числом")
    }

    t.test("В репозитории номера сборки нет") {
        let info = (try? Data(contentsOf: repoRoot.appendingPathComponent("Resources/Info.plist")))
            .flatMap { try? PropertyListSerialization.propertyList(from: $0, format: nil) }
            as? [String: Any] ?? [:]

        t.expect(info["CFBundleVersion"] as? String, "0", "настоящий номер ставит build.sh")
        t.expect(info["CFBundleShortVersionString"] as? String, "1.0",
                 "человеческая версия от номера сборки не зависит")
    }
}
