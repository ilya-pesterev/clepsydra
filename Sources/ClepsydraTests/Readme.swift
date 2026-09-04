import Foundation

/// README — первая и часто единственная страница, которую человек читает перед
/// установкой. Проверяется здесь не текст, а форма: с чего начинается
/// «Установка», названы ли требования и не встречает ли читатель команду в
/// терминале раньше, чем дошёл до раздела для разработчиков.
func checkReadme(_ t: Runner) {

    let readme = documentText("README.md")
    let installSection = documentSection(named: "## Установка", in: readme)
    let developmentDoc = documentText("docs/development.md")
    let beforeDevelopment = readme.components(separatedBy: "## Разработка")[0]

    t.test("«Установка» начинается ссылкой на сам образ") {
        // Не на страницу релизов и не на конкретный тег: адрес
        // `releases/latest/download` не устаревает вместе с версией и отдаёт
        // файл сразу, без промежуточной страницы, на которой человек ищет,
        // что из приложенного качать.
        let firstLine = installSection.split(separator: "\n").first.map(String.init) ?? ""
        t.expect(firstLine.contains("/releases/latest/download/"), true, "первая строка раздела — скачивание образа")
        t.expect(firstLine.contains(".dmg"), true, "ссылка ведёт на образ, а не на страницу")
        t.expect(installSection.contains("git clone"), false, "установка — не сборка")
    }

    t.test("Шагов ровно три: скачать, перетащить, первый запуск") {
        t.expect(numberedSteps(in: installSection), 3)
    }

    t.test("Перетаскивают на ярлык «Applications»") {
        // Именно это слово написано под ярлыком в окне DMG — переводить его
        // в «Программы» значит отправить человека искать не то.
        t.expect(installSection.contains("Applications"), true)
    }

    t.test("Названы требования") {
        t.expect(installSection.contains("Apple Silicon"), true)
        t.expect(installSection.contains("macOS 14"), true)
    }

    t.test("Первый запуск описан точными названиями macOS") {
        expectFirstRunNames(t, in: installSection)
    }

    t.test("Руководство по установке называет первый запуск так же") {
        // README отсылает к нему за подробностями: разойтись им нельзя.
        expectFirstRunNames(t, in: documentText("docs/install.md"))
    }

    t.test("До раздела для разработчиков в README нет ни одной команды") {
        t.expect(beforeDevelopment.contains("```"), false, "команда в терминале — уже не установка")
        t.expect(beforeDevelopment.contains("./build.sh"), false)
        t.expect(beforeDevelopment.contains("xcode-select"), false)
    }

    t.test("Сборка из исходников описана в docs/development.md") {
        t.expect(developmentDoc.contains("git clone"), true, "клонировать репозиторий — шаг сборки")
        t.expect(developmentDoc.contains("./build.sh"), true)
        t.expect(occurrences(of: "docs/development.md", in: readme), 1, "в README на неё одна ссылка")
    }

    t.test("Тон «вы»") {
        // Подпись «Перетащи в папку» на фоне DMG — сознательное исключение;
        // в README её форму не тиражируем.
        let informal = matches(of: "\\b(Скачай|Открой|Перетащи|Запусти|Нажми|Положи)\\b", in: readme)
        t.expect(informal, [], "в документации проекта обращаются на «вы»")
    }
}

/// Сколько в разметке пунктов нумерованного списка.
private func numberedSteps(in text: String) -> Int {
    matches(of: "(?m)^[0-9]+\\. ", in: text).count
}

private func occurrences(of needle: String, in text: String) -> Int {
    text.components(separatedBy: needle).count - 1
}

private func matches(of pattern: String, in text: String) -> [String] {
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
    let whole = NSRange(text.startIndex..., in: text)
    return regex.matches(in: text, range: whole).compactMap {
        Range($0.range, in: text).map { String(text[$0]) }
    }
}
