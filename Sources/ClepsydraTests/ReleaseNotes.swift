import Foundation

/// Описание релиза собирает `Tools/release-notes.sh`. Что изменилось — пишется
/// руками и приходит файлом; всё остальное постоянно от релиза к релизу, и
/// проверяется здесь именно оно: забыть его на странице релиза проще всего.
func checkReleaseNotes(_ t: Runner) {

    let changes = temporaryFile(
        named: "1.0.md",
        contents: "## Что изменилось\n\n- Подменю «Последние дни» в меню.\n"
    )

    t.test("Описание начинается с того, что изменилось") {
        let run = runTool("release-notes.sh", changes)
        t.expect(run.status, 0)
        t.expect(run.printed.hasPrefix("## Что изменилось"), true)
        t.expect(run.printed.contains("Подменю «Последние дни» в меню."), true)
    }

    t.test("В описании названы требования") {
        let notes = runTool("release-notes.sh", changes).printed
        t.expect(notes.contains("Apple Silicon"), true)
        t.expect(notes.contains("macOS 14"), true)
    }

    t.test("В описании есть абзац про первый запуск") {
        // Сборка подписана ad-hoc, и первый двойной щелчок macOS остановит.
        // Без этого абзаца человек решит, что скачал сломанное приложение,
        // а синяя кнопка в том окне — «Переместить в Корзину».
        let notes = runTool("release-notes.sh", changes).printed
        t.expect(notes.contains("Конфиденциальность и безопасность"), true)
        t.expect(notes.contains("Все равно открыть"), true)
        t.expect(notes.contains("Переместить в Корзину"), true)
    }

    t.test("Файлы релиза названы теми же именами, что лягут рядом") {
        let notes = runTool("release-notes.sh", changes).printed
        t.expect(notes.contains("Clepsydra-1.0.dmg"), true)
        t.expect(notes.contains("Clepsydra-1.0.dmg.sha256"), true)
    }

    t.test("Версия в описании следует за Info.plist, а не за скриптом") {
        let notes = runTool("release-notes.sh", changes, temporaryPlist(version: "2.5")).printed
        t.expect(notes.contains("Clepsydra-2.5.dmg"), true)
    }

    t.test("Без списка изменений описание не собирается") {
        let run = runTool("release-notes.sh", missingPath())
        t.expect(run.printed, "", "релиз без «что изменилось» выпускать нечем")
        t.expect(run.status, 1)
    }

    t.test("Пустой список изменений — тоже провал") {
        t.expect(runTool("release-notes.sh", temporaryFile(named: "1.0.md", contents: "\n \n")).status, 1)
    }
}
