import Foundation
import ClepsydraCore

/// Фид обновлений кладёт `Tools/update-feed.sh` — и проверяется снаружи, ровно
/// так, как его зовёт `release.sh`. Разойтись фиду и приложению нельзя: имя
/// файла, поля и адрес архива читает установленная копия, до которой после
/// выпуска уже не дотянуться.
func checkUpdateFeed(_ t: Runner) {

    let changes = temporaryFile(
        named: "1.1.md",
        contents: "## Что изменилось\n\n- Пункт «Обновить» в меню.\n"
    )

    /// Фид, разобранный обратно: проверяем не текст, а то, что из него читается.
    func published(
        version: String = "1.1",
        build: String = "20260904105921",
        notes: String = changes,
        date: String = "2026-09-04T10:59:21Z"
    ) -> (fields: [String: String], status: Int32) {
        let run = runTool("update-feed.sh", version, build, notes, date)
        let object = try? JSONSerialization.jsonObject(with: Data(run.printed.utf8))
        return ((object as? [String: String]) ?? [:], run.status)
    }

    t.test("Имя файла в релизе печатает сам скрипт") {
        // Оно же зашито в приложении: адрес фида собирается из него.
        let run = runTool("update-feed.sh", "--name")
        t.expect(run.printed, "updates.json")
        t.expect(run.status, 0)
        t.expect(run.printed, UpdateFeed.fileName, "имя в коде и в выпуске — одно")
    }

    t.test("Фид — JSON с версией, номером сборки, адресом архива и что изменилось") {
        let feed = published()
        t.expect(feed.status, 0)
        t.expect(feed.fields["version"], "1.1")
        t.expect(feed.fields["build"], "20260904105921")
        t.expect(feed.fields["published"], "2026-09-04T10:59:21Z")
        t.expect(feed.fields["notes"]?.contains("Пункт «Обновить» в меню."), true)
    }

    t.test("Адрес архива ведёт на образ того самого выпуска") {
        // Не на releases/latest: фид описывает конкретную версию, и «последний»
        // за время между чтением фида и скачиванием успеет смениться.
        let dmg = runTool("dmg-name.sh", "--published").printed
        let repository = runTool("origin-repo.sh").printed
        t.expect(published().fields["archive"],
                 "https://github.com/\(repository)/releases/download/v1.1/\(dmg)")
    }

    t.test("Приложение разбирает то, что кладёт выпуск") {
        // Обе стороны проверяются здесь вместе: фид собирает bash, читает Swift,
        // и разойтись им негде.
        let run = runTool("update-feed.sh", "1.1", "20260904105921", changes, "2026-09-04T10:59:21Z")
        t.expect(UpdateFeed.parse(Data(run.printed.utf8)),
                 Update(version: "1.1", build: "20260904105921"))
    }

    t.test("Кавычки и косые в описании не ломают JSON") {
        // Описание пишут руками, и незакрытая кавычка сделала бы фид
        // неразбираемым — то есть молча лишила бы обновления всех.
        let tricky = temporaryFile(
            named: "1.1.md",
            contents: "Строка с \"кавычками\", косой \\ и переносом.\n\nВторой абзац.\n"
        )
        let notes = published(notes: tricky).fields["notes"]
        t.expect(notes?.contains("\"кавычками\""), true)
        t.expect(notes?.contains("косой \\ и"), true)
        t.expect(notes?.contains("\n\nВторой абзац."), true, "абзацы не склеиваются")
    }

    t.test("Без даты берётся текущий момент") {
        let date = runTool("update-feed.sh", "1.1", "20260904105921", changes).printed
        t.expect(date.contains("\"published\""), true)
        t.expect(matches("[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z", in: date).count, 1)
    }

    t.test("Номер сборки — число, иначе выпуска нет") {
        // Установленные копии сравнивают по CFBundleVersion: строка вместо
        // номера оставила бы их без обновления молча.
        t.expect(published(build: "1.1").status, 1)
        t.expect(published(build: "").status, 1)
    }

    t.test("Без версии и без описания фид не собирается") {
        t.expect(published(version: "").status, 1)
        t.expect(published(notes: missingPath()).status, 1)
        t.expect(published(notes: temporaryFile(named: "1.1.md", contents: "\n \n")).status, 1)
    }

    t.test("Выпуск кладёт фид к остальному") {
        // Проверить сам выпуск нечем — он публикует релиз, — поэтому смотрим,
        // что шаг из него не выпал: фид собирается и уходит вместе с образом.
        let release = documentText("release.sh")
        t.expect(release.contains("./Tools/update-feed.sh"), true, "фид собирает тот же скрипт")
        t.expect(release.contains("UPLOAD+=(\"$FEED\")"), true, "фид прикладывается к релизу")
    }
}

private func matches(_ pattern: String, in text: String) -> [String] {
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
    return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap {
        Range($0.range, in: text).map { String(text[$0]) }
    }
}
