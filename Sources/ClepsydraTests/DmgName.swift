import Foundation

/// Имя файла DMG собирает `Tools/dmg-name.sh` — и проверяется снаружи, ровно
/// так, как его зовёт `build.sh`. Смысл проверки один: версия в имени приходит
/// из `Info.plist`, а не записана в скрипте.
func checkDmgName(_ t: Runner) {

    t.test("Имя DMG — Clepsydra и версия из Info.plist") {
        let run = runTool("dmg-name.sh")
        t.expect(run.printed, "Clepsydra-1.0.dmg")
        t.expect(run.status, 0)
    }

    t.test("Версия в имени следует за Info.plist, а не за скриптом") {
        t.expect(runTool("dmg-name.sh", temporaryPlist(version: "2.5")).printed, "Clepsydra-2.5.dmg")
    }

    t.test("Plist без версии — не имя с дырой, а провал") {
        let run = runTool("dmg-name.sh", temporaryPlist(version: ""))
        t.expect(run.printed, "", "пустая версия дала бы Clepsydra-.dmg")
        t.expect(run.status, 1, "сборка должна остановиться, а не собрать образ без имени")
    }
}
