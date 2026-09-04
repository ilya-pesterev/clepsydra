import Foundation

/// Имя файла DMG собирает `Tools/dmg-name.sh` — и проверяется снаружи, ровно
/// так, как его зовёт `build.sh`. Смысл проверки один: версия в имени приходит
/// из `Info.plist`, а не записана в скрипте.
func checkDmgName(_ t: Runner) {

    let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // ClepsydraTests
        .deletingLastPathComponent()   // Sources
        .deletingLastPathComponent()   // корень

    /// Plist приходит снаружи параметром — как момент у номера сборки, иначе
    /// проверить нечем: подменить версию в репозитории ради теста нельзя.
    ///
    /// Отдаёт и код возврата: без него пустая строка от несостоявшегося запуска
    /// не отличается от честного отказа, и проверка отказа зеленела бы даже
    /// после удаления скрипта.
    func dmgName(_ arguments: String...) -> (name: String, status: Int32) {
        let process = Process()
        process.executableURL = repoRoot.appendingPathComponent("Tools/dmg-name.sh")
        process.arguments = arguments
        let out = Pipe()
        process.standardOutput = out
        // Отрицательный случай печатает ошибку — в выводе прогона она лишняя.
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return ("", -1) }
        let printed = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let name = String(data: printed, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return (name, process.terminationStatus)
    }

    /// Info.plist с подменённой человеческой версией — в отдельной папке,
    /// репозиторий остаётся нетронутым.
    func plist(version: String) -> String {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("clepsydra-dmg-name-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let path = directory.appendingPathComponent("Info.plist")
        let body = ["CFBundleShortVersionString": version]
        let data = (try? PropertyListSerialization.data(
            fromPropertyList: body, format: .xml, options: 0)) ?? Data()
        try? data.write(to: path)
        return path.path
    }

    t.test("Имя DMG — Clepsydra и версия из Info.plist") {
        let run = dmgName()
        t.expect(run.name, "Clepsydra-1.0.dmg")
        t.expect(run.status, 0)
    }

    t.test("Версия в имени следует за Info.plist, а не за скриптом") {
        t.expect(dmgName(plist(version: "2.5")).name, "Clepsydra-2.5.dmg")
    }

    t.test("Plist без версии — не имя с дырой, а провал") {
        let run = dmgName(plist(version: ""))
        t.expect(run.name, "", "пустая версия дала бы Clepsydra-.dmg")
        t.expect(run.status, 1, "сборка должна остановиться, а не собрать образ без имени")
    }
}
