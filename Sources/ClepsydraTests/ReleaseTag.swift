import Foundation

/// Тег релиза собирает `Tools/release-tag.sh` — и проверяется снаружи, ровно
/// так, как его зовёт `release.sh`. Смысл проверки один: тег и человеческая
/// версия бандла — одно и то же число, разойтись им нельзя.
func checkReleaseTag(_ t: Runner) {

    // Версия бандла берётся из Info.plist, а не пишется здесь строкой: она
    // растёт с каждым выпуском, и прогон не должен краснеть от этого.
    let version = bundlePlistValue("CFBundleShortVersionString") as? String ?? ""

    t.test("Тег — названная версия с буквой v") {
        let run = runTool("release-tag.sh", version)
        t.expect(run.printed, "v\(version)")
        t.expect(run.status, 0)
    }

    t.test("Версию называют и с буквой v, и без неё") {
        t.expect(runTool("release-tag.sh", "v\(version)").printed, "v\(version)")
    }

    t.test("Версия не та, что в бандле, — отказ до публикации") {
        // 0.9 не станет версией бандла никогда: номера только растут.
        let run = runTool("release-tag.sh", "0.9")
        t.expect(run.printed, "", "тега быть не должно")
        t.expect(run.status, 1, "релиз v0.9 с бандлом версии \(version) не создаётся")
    }

    t.test("Версию надо назвать вслух") {
        // Молча взять её из Info.plist значило бы отменить проверку: сверять
        // стало бы не с чем.
        let run = runTool("release-tag.sh")
        t.expect(run.printed, "")
        t.expect(run.status, 1)
    }

    t.test("Версия сверяется с тем plist, что дали") {
        t.expect(runTool("release-tag.sh", "2.5", temporaryPlist(version: "2.5")).printed, "v2.5")
    }

    t.test("Plist без версии — не тег с дырой, а провал") {
        let run = runTool("release-tag.sh", "1.0", temporaryPlist(version: ""))
        t.expect(run.printed, "", "пустая версия дала бы тег v")
        t.expect(run.status, 1)
    }
}
