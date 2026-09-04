import Foundation
import ClepsydraCore

/// Фид установщика кладёт `Tools/update-installer-feed.sh`. По нему Sparkle
/// скачивает архив, проверяет подпись и заменяет установленную копию — то есть ошибка
/// здесь не показывает лишнюю строку в меню, а оставляет всех без обновления.
///
/// Фидов два, и главное про них — что они не могут разойтись: адрес архива в
/// обоих один, и это проверяется здесь.
func checkInstallerFeed(_ t: Runner) {

    let archive = temporaryFile(named: "Clepsydra.zip", contents: "как будто бандл")

    /// Фид установщика, разобранный обратно: проверяем не текст, а то, что из
    /// него прочтёт Sparkle.
    func published(
        version: String = "1.1",
        build: String = "20260904105921",
        archive: String = archive
    ) -> (item: XMLElement?, enclosure: XMLElement?, status: Int32) {
        let run = runTool(
            "update-installer-feed.sh",
            environment: ["CLEPSYDRA_UPDATE_KEY": testUpdateKey],
            arguments: [version, build, archive]
        )
        let document = try? XMLDocument(xmlString: run.printed)
        let item = (try? document?.nodes(forXPath: "//item"))??.first as? XMLElement
        let enclosure = (try? document?.nodes(forXPath: "//item/enclosure"))??.first as? XMLElement
        return (item, enclosure, run.status)
    }

    func text(_ element: XMLElement?, _ name: String) -> String? {
        element?.elements(forName: name).first?.stringValue
    }

    func attribute(_ element: XMLElement?, _ name: String) -> String? {
        element?.attribute(forName: name)?.stringValue
    }

    t.test("Имя файла в релизе печатает сам скрипт") {
        // Из него же собран SUFeedURL бандла — это сверяет checkUpdateInstaller.
        let run = runTool("update-installer-feed.sh", "--name")
        t.expect(run.printed, "updates.xml")
        t.expect(run.status, 0)
    }

    t.test("Фид установщика — разбираемый XML с версией и номером сборки") {
        let feed = published()
        t.expect(feed.status, 0)
        t.expect(text(feed.item, "sparkle:version"), "20260904105921")
        t.expect(text(feed.item, "sparkle:shortVersionString"), "1.1")
    }

    t.test("Нижняя граница системы — из того же Info.plist, что и у бандла") {
        // Разойдись они, обновление предложилось бы Mac, на котором не запустится.
        t.expect(text(published().item, "sparkle:minimumSystemVersion"),
                 bundlePlistValue("LSMinimumSystemVersion") as? String)
    }

    t.test("Адрес архива тот же, что и в фиде приложения") {
        // Два фида на один выпуск: этот читает установщик, тот — меню. Разойдись
        // адреса, фид обещал бы одно, а ставилось бы другое.
        let changes = temporaryFile(named: "1.1.md", contents: "## Что изменилось\n\n- Что-то.\n")
        let feed = runTool("update-feed.sh", "1.1", "20260904105921", changes)
        let fields = (try? JSONSerialization.jsonObject(with: Data(feed.printed.utf8))) as? [String: String]

        t.expect(attribute(published().enclosure, "url"), fields?["archive"])
        t.expect(attribute(published().enclosure, "url"),
                 "https://github.com/\(runTool("origin-repo.sh").printed)"
                 + "/releases/download/v1.1/\(runTool("update-archive.sh", "--name").printed)")
    }

    t.test("Размер и подпись — того самого архива") {
        let feed = published()
        t.expect(attribute(feed.enclosure, "length"), "\(Data("как будто бандл".utf8).count)")

        let signature = attribute(feed.enclosure, "sparkle:edSignature") ?? ""
        t.expect(runSigning("--verify", archive, signature).status, 0, "подпись сходится с архивом")
        t.expect(signature.isEmpty, false)
    }

    t.test("Без рабочего ключа фида нет вовсе") {
        // Неподписанный архив установщик отвергнет, а узналось бы это уже после
        // выпуска. Ключ здесь ломаем нарочно: связку ключей прогон не трогает,
        // а на машине автора ключ в ней есть — и «ключа нет» пришлось бы
        // изображать её отсутствием.
        let run = runTool(
            "update-installer-feed.sh",
            environment: ["CLEPSYDRA_UPDATE_KEY": "не ключ"],
            arguments: ["1.1", "20260904105921", archive]
        )
        t.expect(run.status, 1)
        t.expect(run.printed.contains("<enclosure"), false, "фид без подписи не печатается вовсе")
    }

    t.test("Номер сборки — число, иначе выпуска нет") {
        // Сравнивает установленную сборку с выпущенной Sparkle, и сравнивает
        // числом: строка оставила бы копии без обновления молча.
        t.expect(published(build: "1.1").status, 1)
        t.expect(published(build: "").status, 1)
    }

    t.test("Без версии и без архива фид не собирается") {
        t.expect(published(version: "").status, 1)
        t.expect(published(archive: missingPath()).status, 1)
    }
}
