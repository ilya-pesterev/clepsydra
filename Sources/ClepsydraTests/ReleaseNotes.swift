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

    t.test("В описании есть путь первого запуска, названия парой") {
        expectFirstRunNames(t, in: runTool("release-notes.sh", changes).printed)
    }

    t.test("Ссылка ведёт в тот же репозиторий, куда уходит релиз") {
        let notes = runTool("release-notes.sh", changes).printed
        let repository = runTool("origin-repo.sh").printed
        t.expect(notes.contains("https://github.com/\(repository)/blob/main/docs/install.md"), true)
    }

    t.test("Файлы релиза названы теми же именами, под которыми выложены") {
        // Описание учит проверять сумму по имени файла: разойдись оно с тем,
        // что приложено к релизу, и команда из описания не сработает.
        let notes = runTool("release-notes.sh", changes).printed
        let published = runTool("dmg-name.sh", "--published").printed
        t.expect(notes.contains(published), true)
        t.expect(notes.contains("\(published).sha256"), true)
        t.expect(notes.contains("Clepsydra-1.0.dmg"), false, "имя с версией уходит только в сборку рядом")
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
