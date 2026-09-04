import Foundation
import ClepsydraCore

/// Обновление: разбор фида, сравнение по номеру сборки, срок тихой проверки и
/// строка пункта меню. Всё это живёт в `ClepsydraCore` — без сети и без
/// системных часов, момент приходит снаружи параметром, — и поэтому покрыто
/// проверками целиком.
func checkUpdates(_ t: Runner) {

    /// Фид, как его кладёт `Tools/update-feed.sh`.
    func feed(
        version: String = "1.1",
        build: String = "20260904105921",
        archive: String = "https://github.com/ilya-pesterev/clepsydra/releases/download/v1.1/Clepsydra.dmg",
        published: String = "2026-09-04T10:59:21Z",
        notes: String = "## Что изменилось\n\n- Пункт «Обновить» в меню.\n"
    ) -> Data {
        let fields = [
            "version": version, "build": build, "archive": archive,
            "published": published, "notes": notes
        ]
        return (try? JSONSerialization.data(withJSONObject: fields)) ?? Data()
    }

    let update = Update(version: "1.1", build: "20260904105921")

    // MARK: Разбор фида

    t.test("Фид разбирается в обновление") {
        t.expect(UpdateFeed.parse(feed()), update)
    }

    t.test("Фид без версии или номера сборки не разбирается") {
        // Молчание, а не догадка: пункт меню останется прежним.
        t.expect(UpdateFeed.parse(feed(version: "")), nil)
        t.expect(UpdateFeed.parse(feed(build: "")), nil)
    }

    t.test("Остальные поля фида приложение не читает") {
        // Адрес архива, дату и «что изменилось» показывать некому: пункт меню
        // называет версию, а подробности человек читает на странице релиза.
        // Отвергать из-за них фид тем более нельзя — чинить его установленной
        // копии нечем, а строгость стоит там, где фид собирают.
        t.expect(UpdateFeed.parse(feed(archive: "", published: "", notes: "")), update)
    }

    t.test("Номер сборки в фиде — число") {
        // Сравнение идёт по CFBundleVersion, а он число: «1.1» вместо номера
        // сборки сравнивать нечем.
        t.expect(UpdateFeed.parse(feed(build: "1.1")), nil)
        t.expect(UpdateFeed.parse(feed(build: "не число")), nil)
    }

    t.test("Не JSON — не обновление") {
        t.expect(UpdateFeed.parse(Data("<html>404</html>".utf8)), nil)
        t.expect(UpdateFeed.parse(Data()), nil)
    }

    t.test("Обновление переживает перезапуск") {
        // В хранилище ложится словарём, как история по дням, и читается тем же
        // разбором, что и фид: двух правил у одного обновления не бывает.
        t.expect(Update(fields: update.stored), update)
        t.expect(Update(fields: [:]), nil)
    }

    // MARK: Сравнение

    t.test("Новее — тот, у кого номер сборки больше") {
        t.expect(update.isNewer(than: "20260904105920"), true)
        t.expect(update.isNewer(than: "20260904105921"), false, "та же сборка — не обновление")
        t.expect(update.isNewer(than: "20260905105921"), false, "сборка новее фида — не откат назад")
    }

    t.test("Сравнение идёт по номеру сборки, а не по человеческой строке") {
        // Версия в фиде может быть какой угодно: решает CFBundleVersion.
        t.expect(Update(version: "9.9", build: "20260904105921")
            .isNewer(than: "20260904105921"), false)
    }

    t.test("Номер, который не число, обновлением не считается") {
        // Своя версия читается из бандла, и подставленная руками ерунда не
        // должна превращаться в «Обновить до 1.1».
        t.expect(update.isNewer(than: "не число"), false)
        t.expect(update.isNewer(than: ""), false)
    }

    // MARK: Состояние пункта меню

    let checked = Date(timeIntervalSince1970: 1_700_000_000)

    t.test("Не проверяли — пункт зовёт проверить") {
        let state = Updates.state(known: nil, lastCheck: nil, installed: "20260904105921")
        t.expect(state, .unknown)
        t.expect(UpdateLabel.title(for: state), "Проверить обновления")
    }

    t.test("Проверили, новее нет — пункт отвечает, что версия последняя") {
        let state = Updates.state(known: update, lastCheck: checked, installed: "20260904105921")
        t.expect(state, .upToDate)
        t.expect(UpdateLabel.title(for: state), "Установлена последняя версия")
    }

    t.test("Есть версия новее — пункт зовёт обновиться и называет версию") {
        let state = Updates.state(known: update, lastCheck: checked, installed: "20260904105920")
        t.expect(state, .ready(update))
        t.expect(UpdateLabel.title(for: state), "Обновить до 1.1")
    }

    t.test("Пока фид не ответил, пункт остаётся прежним") {
        // Состояния «проверяем» у пункта нет: тихая проверка не имеет права
        // трогать меню, пока ей нечего сказать.
        t.expect(Updates.state(known: nil, lastCheck: nil, installed: "20260904105921"), .unknown)
        t.expect(Updates.state(known: update, lastCheck: checked, installed: "20260904105920"),
                 .ready(update))
    }

    t.test("Проверка была, но фид не разобрался — пункт остаётся прежним") {
        // Проверка не удалась, запоминать нечего: зовём проверить снова, а не
        // сообщаем, что версия последняя.
        t.expect(Updates.state(known: nil, lastCheck: checked, installed: "20260904105921"), .unknown)
    }

    // MARK: Срок тихой проверки

    let day: TimeInterval = 24 * 60 * 60

    t.test("Не проверяли ни разу — пора") {
        t.expect(Updates.isDue(lastCheck: nil, lastAttempt: nil, now: checked), true)
    }

    t.test("Проверяем раз в сутки") {
        t.expect(Updates.isDue(lastCheck: checked, lastAttempt: checked,
                               now: checked.addingTimeInterval(day - 1)), false)
        t.expect(Updates.isDue(lastCheck: checked, lastAttempt: checked,
                               now: checked.addingTimeInterval(day)), true)
    }

    t.test("Неудачная проверка не долбит сеть каждую секунду") {
        // Попытка была, а проверки не случилось: фид не ответил. Ждём час,
        // а не сутки, — но и не секунду.
        t.expect(Updates.isDue(lastCheck: nil, lastAttempt: checked,
                               now: checked.addingTimeInterval(60)), false)
        t.expect(Updates.isDue(lastCheck: nil, lastAttempt: checked,
                               now: checked.addingTimeInterval(60 * 60)), true)
    }

    t.test("Часы отмотали назад — проверяем, а не ждём вечно") {
        t.expect(Updates.isDue(lastCheck: checked, lastAttempt: checked,
                               now: checked.addingTimeInterval(-day)), true)
    }

    // MARK: Адреса

    t.test("Фид лежит по постоянному адресу") {
        // releases/latest/download — тот же приём, что у образа в README:
        // адрес не меняется от релиза к релизу, иначе установленные копии
        // перестанут находить фид после первого же выпуска.
        t.expect(UpdateFeed.address.absoluteString,
                 "https://github.com/ilya-pesterev/clepsydra/releases/latest/download/updates.json")
    }

    t.test("Запасной путь ведёт на страницу последнего релиза") {
        t.expect(UpdateFeed.releasePage.absoluteString,
                 "https://github.com/ilya-pesterev/clepsydra/releases/latest")
    }

    t.test("Обновление заведено в словаре, а решение записано") {
        // Слова пункта меню — часть решения: разойдись меню и словарь, в
        // проекте завёлся бы второй язык.
        let context = documentText("CONTEXT.md")
        t.expect(context.contains("## Обновление"), true)
        t.expect(context.contains("## Фид"), true)
        for title in [UpdateLabel.title(for: .unknown), UpdateLabel.title(for: .upToDate)] {
            t.expect(context.contains("«\(title)»"), true, "в словаре нет «\(title)»")
        }

        let decision = documentText("docs/adr/0009-updates-are-checked-quietly.md")
        t.expect(decision.contains("Меню сообщает, а не обращается"), true,
                 "почему меню не считается обращением к человеку — главное в решении")
    }

    t.test("Адреса ведут туда же, куда уходит релиз") {
        // Репозиторий в коде и origin, куда release.sh кладёт релиз, разойтись
        // не могут: разойдись они, приложение спрашивало бы пустоту.
        let repository = runTool("origin-repo.sh").printed
        t.expect(UpdateFeed.address.absoluteString.contains("github.com/\(repository)/"), true)
        t.expect(UpdateFeed.releasePage.absoluteString.contains("github.com/\(repository)/"), true)
    }
}
