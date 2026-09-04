import Foundation

/// Корень репозитория — от пути этого файла, а не от рабочей папки: прогон
/// запускают и не из корня.
let repositoryRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()   // ClepsydraTests
    .deletingLastPathComponent()   // Sources
    .deletingLastPathComponent()   // корень

/// Запускает скрипт из `Tools/` ровно так, как его зовёт сборка.
///
/// Отдаёт и код возврата: без него пустая строка от несостоявшегося запуска не
/// отличается от честного отказа, и проверка отказа зеленела бы даже после
/// удаления скрипта. Ошибки скрипт печатает в stderr, и в выводе прогона они
/// лишние — отрицательных случаев здесь больше, чем положительных.
func runTool(_ name: String, _ arguments: String...) -> (printed: String, status: Int32) {
    let process = Process()
    process.executableURL = repositoryRoot.appendingPathComponent("Tools/\(name)")
    process.arguments = arguments
    let out = Pipe()
    process.standardOutput = out
    process.standardError = FileHandle.nullDevice
    do { try process.run() } catch { return ("", -1) }
    let printed = out.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    let text = String(data: printed, encoding: .utf8)?
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return (text, process.terminationStatus)
}

/// Отдельная папка под каждый случай: репозиторий остаётся нетронутым, а
/// файлы разных проверок не путаются между собой.
private func temporaryDirectory() -> URL {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("clepsydra-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}

/// Info.plist с подменённой человеческой версией: подменить версию в
/// репозитории ради проверки нельзя, а сверять её с чем-то надо.
func temporaryPlist(version: String) -> String {
    let path = temporaryDirectory().appendingPathComponent("Info.plist")
    let body = ["CFBundleShortVersionString": version]
    let data = (try? PropertyListSerialization.data(
        fromPropertyList: body, format: .xml, options: 0)) ?? Data()
    try? data.write(to: path)
    return path.path
}

func temporaryFile(named name: String, contents: String) -> String {
    let path = temporaryDirectory().appendingPathComponent(name)
    try? contents.write(to: path, atomically: true, encoding: .utf8)
    return path.path
}

/// Путь, по которому файла нет, — для случаев «файл не положили».
func missingPath() -> String {
    temporaryDirectory().appendingPathComponent("нет-такого").path
}
