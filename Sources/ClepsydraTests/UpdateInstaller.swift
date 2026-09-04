import Foundation
import ClepsydraCore

/// Установщик обновлений живёт наполовину в бандле, наполовину в скриптах:
/// адрес фида и открытая половина ключа лежат в `Info.plist`, фреймворк
/// кладёт и подписывает `build.sh`, архив с фидом прикладывает `release.sh`.
/// Запустить это в прогоне нечем — сборка одна на всю машину, — поэтому
/// проверяется, что шаги на месте и говорят одно и то же.
func checkUpdateInstaller(_ t: Runner) {

    t.test("Установщик спрашивает фид там же, куда его кладёт выпуск") {
        // Адреса этого приложение не знает: фид установщика спрашивает Sparkle,
        // а SUFeedURL написан в Info.plist руками. Поэтому собираем его здесь
        // из тех же частей, что и выпуск, — репозиторий из origin, имя файла
        // печатает сам скрипт.
        let repository = runTool("origin-repo.sh").printed
        let name = runTool("update-installer-feed.sh", "--name").printed

        t.expect(repository, UpdateFeed.repository, "оба фида лежат в одном релизе")
        t.expect(bundlePlistValue("SUFeedURL") as? String,
                 "https://github.com/\(repository)/releases/latest/download/\(name)")
    }

    t.test("Автопроверка установщика выключена") {
        // Проверяет обновления сама Clepsydra: раз в сутки и молча (ADR-0009).
        // Второе расписание — со своим окном при запуске — отменяло бы ADR-0001.
        t.expect(bundlePlistValue("SUEnableAutomaticChecks") as? Bool, false)
    }

    t.test("Открытая половина ключа лежит в бандле") {
        // Потеряйся она — установщик не заведётся вовсе, и «Обновить» откроет
        // страницу релиза, как до него. Что она от того же ключа, которым
        // подписывается архив, сверяет release.sh: связку ключей прогон не
        // трогает, а на чужой машине её и нет.
        let key = bundlePlistValue("SUPublicEDKey") as? String
        t.expect(Data(base64Encoded: key ?? "")?.count, 32,
                 "открытая половина ed25519 — 32 байта в base64")
    }

    t.test("Сборка кладёт фреймворк в бандл и подписывает изнутри наружу") {
        // Проверить подписью нечего: прогон идёт до сборки бандла. Смотрим,
        // что шаги не выпали — без фреймворка приложение не запустится вовсе,
        // а подписанный последним фреймворк ломает подпись приложения.
        let build = documentText("build.sh")
        t.expect(build.contains("ditto \"$BIN_PATH/Sparkle.framework\" \"$SPARKLE\""), true,
                 "фреймворк едет в бандл")
        t.expect(build.contains("Contents/Frameworks/Sparkle.framework"), true)
        t.expect(build.contains("codesign --verify --strict \"$APP\""), true,
                 "подпись бандла проверяется на месте")

        // Порядок подписи: вложенное, потом фреймворк, потом приложение.
        let body = build.range(of: "sign_bundle() {").map { String(build[$0.upperBound...]) } ?? ""
        let signing = body.range(of: "\n}").map { String(body[..<$0.lowerBound]) } ?? ""
        let order = ["Updater.app", "Autoupdate", "\"$SPARKLE\"", "\"$APP\""]
        let places = order.map { signing.range(of: $0)?.lowerBound }

        t.expect(places.contains(where: { $0 == nil }), false, "шаг подписи потерян")
        t.expect(places.compactMap { $0 }, places.compactMap { $0 }.sorted(),
                 "подписывают изнутри наружу")
    }

    t.test("Лишнее из фреймворка выбрасывается вместе со ссылкой на него") {
        // Ссылка на выброшенную папку остаётся висеть в пустоте и уезжает
        // такой людям: у фреймворка на верхнем уровне символические ссылки на
        // Versions/Current, и убирать надо обе стороны.
        let build = documentText("build.sh")
        t.expect(build.contains("for unused in XPCServices Headers PrivateHeaders Modules"), true,
                 "из бандла выброшены и службы, и заголовки")
        t.expect(build.contains("rm -rf \"$SPARKLE_VERSION/$unused\" \"$SPARKLE/$unused\""), true,
                 "убирается и папка, и ссылка на неё")
    }

    t.test("Выпуск кладёт архив и фид установщика к остальному") {
        // Проверить сам выпуск нечем — он публикует релиз, — поэтому смотрим,
        // что шаги из него не выпали.
        let release = documentText("release.sh")
        t.expect(release.contains("./Tools/update-archive.sh"), true, "архив собирает тот же скрипт")
        t.expect(release.contains("./Tools/update-installer-feed.sh"), true, "фид установщика — тоже")
        t.expect(release.contains("UPLOAD+=(\"$INSTALLER_FEED\")"), true, "фид прикладывается к релизу")
    }

    t.test("Выпуск не выйдет ключом, которого нет в бандле") {
        // Архив, подписанный ключом, чья открытая половина не уехала в бандле,
        // не поставится ни на одну установленную копию — и узналось бы это
        // после выпуска, когда чинить уже нечем.
        let release = documentText("release.sh")
        t.expect(release.contains("./Tools/sign-update.swift --public"), true,
                 "ключ из связки сверяется с ключом в бандле")
        t.expect(release.contains("SUPublicEDKey"), true)
    }
}
