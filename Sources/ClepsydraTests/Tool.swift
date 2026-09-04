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

/// Текст документа от корня репозитория.
///
/// Файла нет — прогон падает сразу, а не отдаёт пустую строку: проверки вида
/// «команды здесь нет» на пустоте зеленеют, и переименованный документ прошёл
/// бы незамеченным. Та же причина, по которой `runTool` отдаёт код возврата.
func documentText(_ path: String) -> String {
    let url = repositoryRoot.appendingPathComponent(path)
    guard let text = try? String(contentsOf: url, encoding: .utf8) else {
        FileHandle.standardError.write("✗ нет документа \(path)\n".data(using: .utf8)!)
        exit(1)
    }
    return text
}

/// Раздел разметки: от заголовка до следующего заголовка того же уровня.
func documentSection(named heading: String, in text: String) -> String {
    guard let start = text.range(of: heading) else { return "" }
    let body = String(text[start.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
    guard let next = body.range(of: "\n## ") else { return body }
    return String(body[..<next.lowerBound])
}

/// Строка в одну линию: переносы и отступы разметки схлопнуты в пробелы.
/// Иначе «Move to Trash», разорванное переносом, не найдётся подстрокой.
func flattened(_ text: String) -> String {
    text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
}

/// Путь первого запуска описан и в README, и в описании релиза: сборка
/// подписана ad-hoc, и первый двойной щелчок macOS остановит. Без этого абзаца
/// человек решит, что скачал сломанное приложение, а синяя кнопка по умолчанию
/// в том окне — «Переместить в Корзину».
///
/// Названия даны парой, по-русски и по-английски: macOS у всех на разном
/// языке, и человек ищет глазами ту самую строку. Разойтись двум текстам
/// нельзя, поэтому проверка у них общая.
func expectFirstRunNames(_ t: Runner, in text: String, line: Int = #line) {
    let flat = flattened(text)
    let names = [
        "Переместить в Корзину", "Move to Trash",
        "Конфиденциальность и безопасность", "Privacy & Security",
        "Все равно открыть", "Open Anyway"
    ]
    for name in names {
        t.expect(flat.contains(name), true, "не названо «\(name)»", line: line)
    }
}
