import Foundation

/// Имя файла DMG собирает `Tools/dmg-name.sh` — и проверяется снаружи, ровно
/// так, как его зовёт `build.sh`. Смысл проверки один: версия в имени приходит
/// из `Info.plist`, а не записана в скрипте.
func checkDmgName(_ t: Runner) {

    t.test("Имя DMG — Clepsydra и версия из Info.plist") {
        // Версия берётся из бандла, а не пишется здесь строкой: она растёт с
        // каждым выпуском, и прогон не должен краснеть от этого.
        let version = bundlePlistValue("CFBundleShortVersionString") as? String ?? ""
        let run = runTool("dmg-name.sh")
        t.expect(run.printed, "Clepsydra-\(version).dmg")
        t.expect(run.status, 0)
    }

    t.test("Версия в имени следует за Info.plist, а не за скриптом") {
        t.expect(runTool("dmg-name.sh", temporaryPlist(version: "2.5")).printed, "Clepsydra-2.5.dmg")
    }

    t.test("В релизе образ лежит под именем без версии") {
        // На это имя ведёт первый пункт «Установки» в README через
        // releases/latest/download: версия в нём сделала бы ссылку одноразовой.
        let run = runTool("dmg-name.sh", "--published")
        t.expect(run.printed, "Clepsydra.dmg")
        t.expect(run.status, 0)
    }

    t.test("Релизному имени plist не нужен") {
        // Версии оно не знает, поэтому и не спрашивает: plist без версии
        // отваливает сборку рядом, но не публикацию.
        t.expect(runTool("dmg-name.sh", "--published", temporaryPlist(version: "")).printed, "Clepsydra.dmg")
    }

    t.test("Plist без версии — не имя с дырой, а провал") {
        let run = runTool("dmg-name.sh", temporaryPlist(version: ""))
        t.expect(run.printed, "", "пустая версия дала бы Clepsydra-.dmg")
        t.expect(run.status, 1, "сборка должна остановиться, а не собрать образ без имени")
    }
}
